package;

import js.node.ChildProcess;

using api.IdeckiaApi;
using StringTools;

typedef Props = {
	@:editable("prop_game", "")
	var game:String;
}

typedef GameInfo = {
	var appid:UInt;
	var name:String;
}

@:name("launch-steam-game")
@:description("action_description")
@:localize("loc")
class LaunchSteamGame extends IdeckiaAction {
	var launchCmd = '';

	static var GAMES_LIST:Array<GameInfo> = [];

	override public function init(initialState:ItemState):js.lib.Promise<ItemState> {
		launchCmd = switch Sys.systemName() {
			case "Linux": 'xdg-open';
			case "Mac": 'open';
			case "Windows": 'start';
			case _: '';
		};
		return new js.lib.Promise((resolve, reject) -> {
			updateGameList();
			var gameFound = false;
			if (props.game != '' && (initialState.icon == null || initialState.icon == '')) {
				for (g in GAMES_LIST) {
					if (g.name == props.game) {
						gameFound = true;
						getImage(g.appid).then(data -> initialState.icon = haxe.crypto.Base64.encode(data)).catchError(e -> {
							core.log.error('Error getting ${g.name} (appid=${g.appid}) thumbnail: $e');
							initialState.text = g.name;
						}).finally(() -> resolve(initialState));
					}
				}
			}
			if (!gameFound)
				resolve(initialState);
		});
	}

	public function execute(currentState:ItemState):js.lib.Promise<ActionOutcome> {
		var launchAppId = -1;
		for (info in GAMES_LIST) {
			if (info.name == props.game) {
				launchAppId = info.appid;
				break;
			}
		}

		if (launchCmd != '' && props.game != '' && launchAppId != -1)
			ChildProcess.spawn('$launchCmd steam://rungameid/$launchAppId', {shell: true, detached: true, stdio: Ignore});
		else
			core.dialog.error(Loc.game_not_found_title.tr(), Loc.game_not_found_body.tr([props.game]));

		return js.lib.Promise.resolve(new ActionOutcome({state: currentState}));
	}

	function updateGameList() {
		GAMES_LIST = [];
		for (steamPath in getSteamPaths()) {
			try {
				for (f in sys.FileSystem.readDirectory(steamPath)) {
					if (!f.endsWith('.acf'))
						continue;

					GAMES_LIST.push(extractFromAcf(sys.io.File.getContent(haxe.io.Path.join([steamPath, f]))));
				};
			} catch (err) {
				core.log.error('Error reading Steam installation directory $err');
			}
		}
	}

	function extractFromAcf(acfContent:String):GameInfo {
		var appid = 0;
		var name = 'nogame';
		for (line in ~/\r?\n/g.split(acfContent)) {
			if (appid != 0 && name != 'nogame')
				break;
			if (line.contains('"appid"'))
				appid = Std.parseInt(line.replace('appid', '').replace('"', '').trim());
			if (line.contains('"name"'))
				name = line.replace('name', '').replace('"', '').trim();
		}

		return {
			appid: appid,
			name: name
		};
	}

	function getSteamPaths() {
		return switch Sys.systemName() {
			case "Linux":
				final homeDir = js.Node.process.env.get('HOME');
				[
					'$homeDir/.steam/steam/steamapps',
					'$homeDir/.var/app/com.valvesoftware.Steam/data/Steam/steamapps'
				];
			case "Mac":
				final homeDir = js.Node.process.env.get('HOME');
				['$homeDir/Library/Application Support/Steam/steamapps'];
			case "Windows":
				final programFiles = js.Node.process.env.get('ProgramFiles');
				final programFilesx86 = js.Node.process.env.get('ProgramFiles(x86)');
				final username = js.Node.process.env.get('USERNAME');

				[
					'$programFiles\\Steam\\steamapps',
					'$programFilesx86\\Steam\\steamapps',
					'z:\\home\\deck\\.steam\\steam\\steamapps',
					'z:\\home\\$username\\.steam\\steam\\steamapps'
				];
			case _:
				[];
		};
	}

	public function getActionDescriptor():js.lib.Promise<ActionDescriptor> {
		return new js.lib.Promise((resolve, reject) -> {
			var descriptor = _getActionDescriptor();
			var gameNames = GAMES_LIST.map(info -> info.name);

			for (prop in descriptor.props)
				if (prop.name == 'game')
					prop.possibleValues = gameNames;

			resolve(descriptor);
		});
	}

	public function getImage(appId:UInt) {
		return new js.lib.Promise((resolve, reject) -> {
			final endpoint = 'https://cdn.cloudflare.steamstatic.com/steam/apps/$appId/hero_capsule.jpg';
			var http = new haxe.Http(endpoint);
			http.addHeader('Accept', 'application/json');
			http.onError = reject;
			http.onBytes = resolve;
			http.request();
		});
	}
}

extends Node
class_name PlatformBridge

signal initialized(success: bool)
signal data_loaded(data: Dictionary)
signal data_saved(success: bool)
signal ad_watched(success: bool, reward_type: String)

enum Platform { NONE, YANDEX, VK, TELEGRAM, CRAZY, LOCAL }
var current_platform: Platform = Platform.LOCAL
var player_data: Dictionary = {}
var save_debounce_timer: Timer = null
var last_ad_time: int = 0
const AD_COOLDOWN_SECONDS: int = 180

func _ready() -> void:
    _detect_platform()
    _init_save_debounce()

func _detect_platform() -> void:
    if OS.has_feature("web"):
        var js = JavaScriptBridge
        # Проверка Яндекс SDK
        if js.is_object_available("YaGames") or js.eval("typeof YaGames !== 'undefined'"):
            current_platform = Platform.YANDEX
        # Проверка VK Bridge
        elif js.is_object_available("VK") or js.eval("typeof VK !== 'undefined'"):
            current_platform = Platform.VK
        # Проверка Telegram
        elif js.is_object_available("Telegram") or js.eval("typeof Telegram !== 'undefined'"):
            current_platform = Platform.TELEGRAM
        # Проверка CrazyGames
        elif js.is_object_available("CrazyGames") or js.eval("typeof CrazyGames !== 'undefined'"):
            current_platform = Platform.CRAZY
    print("Detected platform: ", Platform.keys()[current_platform])

func init() -> void:
    match current_platform:
        Platform.YANDEX:
            _init_yandex()
        Platform.VK:
            _init_vk()
        Platform.TELEGRAM:
            _init_telegram()
        Platform.CRAZY:
            _init_crazygames()
        _:
            emit_signal("initialized", true)

func _init_yandex() -> void:
    JavaScriptBridge.eval("""
        if (typeof YaGames !== 'undefined') {
            YaGames.init().then(ysdk => {
                window.ysdk = ysdk;
                console.log('Yandex SDK initialized');
            }).catch(console.error);
        }
    """)
    emit_signal("initialized", true)

func _init_vk() -> void:
    JavaScriptBridge.eval("""
        if (typeof VK !== 'undefined') {
            VK.Bridge.init({ apiVersion: '5.103' });
            console.log('VK Bridge initialized');
        }
    """)
    emit_signal("initialized", true)

func _init_telegram() -> void:
    JavaScriptBridge.eval("""
        if (typeof Telegram !== 'undefined' && Telegram.WebApp) {
            window.telegramApp = Telegram.WebApp;
            telegramApp.ready();
            telegramApp.expand();
            console.log('Telegram WebApp initialized');
        }
    """)
    emit_signal("initialized", true)

func _init_crazygames() -> void:
    JavaScriptBridge.eval("console.log('CrazyGames SDK ready');")
    emit_signal("initialized", true)

func _init_save_debounce() -> void:
    save_debounce_timer = Timer.new()
    save_debounce_timer.wait_time = 5.0
    save_debounce_timer.one_shot = true
    add_child(save_debounce_timer)

func load_data() -> Dictionary:
    match current_platform:
        Platform.YANDEX:
            return _load_yandex_data()
        Platform.VK:
            return _load_vk_data()
        Platform.TELEGRAM:
            return _load_telegram_data()
        _:
            return _load_local_data()

func _load_yandex_data() -> Dictionary:
    var js_code = """
        (function() {
            try {
                if (window.ysdk && window.ysdk.getPlayer) {
                    return window.ysdk.getPlayer().then(player => {
                        return player.getData(['saveData']).then(data => {
                            return JSON.stringify(data.saveData || {});
                        });
                    }).catch(() => '{}');
                }
                return '{}';
            } catch(e) { return '{}'; }
        })();
    """
    var result = JavaScriptBridge.eval(js_code)
    return JSON.parse_string(result) if result else {}

func _load_vk_data() -> Dictionary:
    var js_code = """
        (function() {
            try {
                if (typeof VK !== 'undefined' && VK.Bridge) {
                    return VK.Bridge.send('VKWebAppStorageGet', {'keys': ['arena_bowl_save']})
                        .then(data => JSON.stringify(data.response[0]?.value || '{}'))
                        .catch(() => '{}');
                }
                return '{}';
            } catch(e) { return '{}'; }
        })();
    """
    var result = JavaScriptBridge.eval(js_code)
    return JSON.parse_string(result) if result else {}

func _load_telegram_data() -> Dictionary:
    return _load_local_data()

func _load_local_data() -> Dictionary:
    var js_code = "localStorage.getItem('arena_bowl_save') || '{}'"
    var result = JavaScriptBridge.eval(js_code)
    return JSON.parse_string(result) if result else {}

func save_data(data: Dictionary) -> void:
    if save_debounce_timer.time_left > 0:
        return
    
    match current_platform:
        Platform.YANDEX:
            _save_yandex_data(data)
        Platform.VK:
            _save_vk_data(data)
        _:
            _save_local_data(data)
    
    save_debounce_timer.start()

func _save_yandex_data(data: Dictionary) -> void:
    var json_str = JSON.stringify(data)
    JavaScriptBridge.eval("""
        if (window.ysdk && window.ysdk.getPlayer) {
            window.ysdk.getPlayer().then(player => {
                player.setData({'saveData': %s}).catch(console.error);
            });
        }
    """ % json_str)

func _save_vk_data(data: Dictionary) -> void:
    var json_str = JSON.stringify(data)
    JavaScriptBridge.eval("""
        if (typeof VK !== 'undefined' && VK.Bridge) {
            VK.Bridge.send('VKWebAppStorageSet', {
                'key': 'arena_bowl_save',
                'value': %s
            });
        }
    """ % json_str)

func _save_local_data(data: Dictionary) -> void:
    var json_str = JSON.stringify(data)
    JavaScriptBridge.eval("localStorage.setItem('arena_bowl_save', '%s');" % json_str.replace("'", "\\'"))

func show_interstitial() -> void:
    var current_time = Time.get_unix_time_from_system()
    if current_time - last_ad_time < AD_COOLDOWN_SECONDS:
        print("Ad on cooldown")
        return
    
    match current_platform:
        Platform.YANDEX:
            JavaScriptBridge.eval("""
                if (window.ysdk) {
                    window.ysdk.adv.showFullscreenAdv({
                        callbacks: {
                            onClose: function(wasShown) { console.log('Interstitial closed'); },
                            onError: function(error) { console.error('Interstitial error', error); }
                        }
                    });
                }
            """)
            last_ad_time = current_time
        Platform.VK:
            JavaScriptBridge.eval("""
                if (typeof VK !== 'undefined' && VK.Bridge) {
                    VK.Bridge.send('VKWebAppShowNativeAds', {'ad_format': 'interstitial'});
                }
            """)
            last_ad_time = current_time

func show_rewarded_video(reward_type: String = "coins") -> void:
    match current_platform:
        Platform.YANDEX:
            JavaScriptBridge.eval("""
                if (window.ysdk) {
                    window.ysdk.adv.showRewardedVideo({
                        callbacks: {
                            onOpen: function() { console.log('Rewarded video opened'); },
                            onRewarded: function() { 
                                console.log('Rewarded!');
                                window.dispatchEvent(new CustomEvent('ad_reward', {detail: {type: '%s'}}));
                            },
                            onClose: function() { console.log('Rewarded video closed'); },
                            onError: function(e) { console.error('Rewarded video error', e); }
                        }
                    });
                }
            """ % reward_type)
        Platform.VK:
            JavaScriptBridge.eval("""
                if (typeof VK !== 'undefined' && VK.Bridge) {
                    VK.Bridge.send('VKWebAppShowNativeAds', {
                        'ad_format': 'rewarded_video'
                    }).then(data => {
                        if (data.result) {
                            window.dispatchEvent(new CustomEvent('ad_reward', {detail: {type: '%s'}}));
                        }
                    });
                }
            """ % reward_type)

func rate_game() -> void:
    match current_platform:
        Platform.YANDEX:
            JavaScriptBridge.eval("""
                if (window.ysdk) {
                    window.ysdk.feedback.canReview().then(({value}) => {
                        if (value) {
                            window.ysdk.feedback.requestReview();
                        }
                    });
                }
            """)

func get_player_id() -> String:
    var js_code = """
        (function() {
            if (window.ysdk && window.ysdk.getPlayer) {
                try {
                    return window.ysdk.getPlayer().then(p => p.getID()).catch(() => 'anonymous');
                } catch(e) { return 'anonymous'; }
            }
            return 'player_' + Date.now();
        })();
    """
    var result = JavaScriptBridge.eval(js_code)
    return result if result else str(Time.get_ticks_usec())

func is_platform_supported(feature: String) -> bool:
    match feature:
        "cloud_save":
            return current_platform in [Platform.YANDEX, Platform.VK]
        "ads":
            return current_platform in [Platform.YANDEX, Platform.VK, Platform.CRAZY]
        "rating":
            return current_platform == Platform.YANDEX
        _:
            return false

func get_platform_name() -> String:
    return Platform.keys()[current_platform]

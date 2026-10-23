import Foundation

/// What macOS keeps for its own services under a plain name in the Library folders Peel searches. No app claims one by
/// its name, so an app called Knowledge never takes `Application Support/Knowledge`. Each name comes with what in the
/// sealed system proves it.
enum SystemFolders {
    /// What in the sealed system proves that a name is macOS's.
    enum Proof: Sendable {
        /// A part of the sealed system called by the name: a framework, a program, or the sandbox profile of one.
        case part(String)
        /// A program or a sandbox profile of the sealed system that holds `naming`.
        case file(String, naming: String)
        /// An image in the dyld shared cache that holds `naming`.
        case image(String, naming: String)
        /// A proof only macOS `version` and earlier hold: a later macOS took the part away, and a Mac that ran one
        /// still keeps the folder.
        indirect case through(Int, Proof)
    }

    static let applicationSupport: [String: Proof] = [
        "Accessibility": .through(26, .file("/System/Library/ExtensionKit/Extensions/AccessibilitySettingsExtension.appex/Contents/MacOS/AccessibilitySettingsExtension", naming: "Library/Application Support/Accessibility")),
        "AddressBook": .file("/System/Library/Sandbox/Profiles/com.apple.iMessage.addressbook.sb", naming: "/Library/Application Support/AddressBook"),
        "Animoji": .file("/System/Library/Sandbox/Profiles/com.apple.avatarsd.sb", naming: "/Library/Application Support/Animoji"),
        "App Store": .file("/System/Library/Frameworks/StoreKit.framework/Support/storekitagent", naming: "Library/Application Support/App Store"),
        "Apple": .file("/System/Library/Sandbox/Profiles/com.apple.AssetCacheManagerService.sb", naming: "/Library/Application Support/Apple"),
        "AppleIDAccountInfo": .file("/usr/libexec/sharingd", naming: "Library/Application Support/AppleIDAccountInfo"),
        "ApplePushService": .part("/System/Library/PrivateFrameworks/ApplePushService.framework"),
        "AppStore": .file("/System/Library/Sandbox/Profiles/com.apple.AppStoreDaemon.StorePrivilegedTaskService.sb", naming: "/Library/Application Support/AppStore"),
        "AppStoreContent": .file("/System/Library/PrivateFrameworks/AppStoreDaemon.framework/Versions/A/XPCServices/com.apple.AppStoreDaemon.StorePrivilegedTaskService.xpc/Contents/MacOS/com.apple.AppStoreDaemon.StorePrivilegedTaskService", naming: "Library/Application Support/AppStoreContent"),
        "assistantd": .file("/System/Library/Sandbox/Profiles/com.apple.assistantd.transcoded.sb", naming: "/Library/Application Support/assistantd"),
        "bookdatastored": .file("/System/Library/PrivateFrameworks/BookDataStore.framework/Support/bookdatastored", naming: "Library/Application Support/bookdatastored"),
        "BTServer": .file("/usr/sbin/bluetoothd", naming: "Library/Application Support/BTServer"),
        "CallHistoryDB": .file("/System/Library/Sandbox/Profiles/com.apple.GameOverlayUI.sb", naming: "/Library/Application Support/CallHistoryDB"),
        "Certificate Authority": .file("/usr/sbin/slapconfig", naming: "Library/Application Support/Certificate Authority"),
        "CloudDocs": .file("/System/Library/Sandbox/Profiles/com.apple.CloudDocsDaemon.container-metadata-extractor.sb", naming: "/Library/Application Support/CloudDocs"),
        "contactsd": .file("/System/Library/Sandbox/Profiles/com.apple.contactsd.sb", naming: "/Library/Application Support/contactsd"),
        "CrashReporter": .file("/System/Library/CoreServices/SubmitDiagInfo", naming: "Library/Application Support/CrashReporter"),
        "DifferentialPrivacy": .file("/System/Library/Sandbox/Profiles/com.apple.dprivacyd.agent.sb", naming: "/Library/Application Support/DifferentialPrivacy"),
        "Directory Access": .file("/System/Library/CoreServices/Applications/Directory Utility.app/Contents/PlugIns/LDAPv3.daplug/Contents/MacOS/LDAPv3", naming: "Library/Application Support/Directory Access"),
        "DiskImages": .part("/System/Library/PrivateFrameworks/DiskImages.framework"),
        "DumpPanic": .file("/usr/libexec/DumpPanic", naming: "Library/Application Support/DumpPanic"),
        "FaceTime": .file("/System/Library/Sandbox/Profiles/com.apple.FaceTime.FTConversationService.sb", naming: "/Library/Application Support/FaceTime"),
        "familycircled": .file("/System/Library/Sandbox/Profiles/com.apple.familycircled.sb", naming: "/Library/Application Support/familycircled"),
        "fdesetup": .file("/usr/bin/fdesetup", naming: "Library/Application Support/fdesetup"),
        "FileProvider": .file("/System/Library/Sandbox/Profiles/com.apple.fileproviderd.sb", naming: "/Library/Application Support/FileProvider"),
        "homeenergyd": .file("/System/Library/Sandbox/Profiles/com.apple.homeenergyd.sb", naming: "/Library/Application Support/homeenergyd"),
        "icdd": .file("/System/Library/Sandbox/Profiles/com.apple.icdd.sb", naming: "/Library/Application Support/icdd"),
        "iCloud": .part("/System/Library/CoreServices/iCloud.app"),
        "identityservicesd": .file("/System/Library/Sandbox/Profiles/com.apple.identityservicesd.sb", naming: "/Library/Application Support/identityservicesd"),
        "iLifeAssetManagement": .file("/System/Library/CoreServices/UAUPlugins/PhotosUserAccountUpdaterPlugin.bundle/Contents/MacOS/PhotosUserAccountUpdaterTool", naming: "Library/Application Support/iLifeAssetManagement"),
        "iLifeMediaBrowser": .part("/System/Library/PrivateFrameworks/iLifeMediaBrowser.framework"),
        "Knowledge": .file("/System/Library/Sandbox/Profiles/com.apple.knowledge-agent.sb", naming: "/Library/Application Support/Knowledge"),
        "livefsd": .file("/System/Library/Sandbox/Profiles/com.apple.fskit.fskit_agent.sb", naming: "/Library/Application Support/livefsd"),
        "locationaccessstored": .part("/usr/libexec/locationaccessstored"),
        "Managed Background Assets Helper Service": .file("/System/Library/Sandbox/Profiles/com.apple.backgroundassets.managed.helper.service.sb", naming: "/Library/Application Support/Managed Background Assets Helper Service"),
        "MobileSync": .file("/System/Library/PrivateFrameworks/StorageManagement.framework/PlugIns/iOSFilesStorageExtension.appex/Contents/MacOS/iOSFilesStorageExtension", naming: "Library/Application Support/MobileSync"),
        "networkserviceproxy": .file("/System/Library/Sandbox/Profiles/com.apple.networkserviceproxy.sb", naming: "/Library/Application Support/networkserviceproxy"),
        "Quick Look": .file("/System/Library/Sandbox/Profiles/com.apple.quicklook.ThumbnailsAgent.sb", naming: "/Library/Application Support/Quick Look"),
        "Rapport": .file("/System/Library/Sandbox/Profiles/com.apple.rapportd.sb", naming: "/Library/Application Support/Rapport"),
        "SESStorage": .file("/usr/libexec/seserviced", naming: "Library/Application Support/SESStorage"),
        "SNLUOverrides.sqlite": .file("/System/Library/Sandbox/Profiles/com.apple.assistantd.transcoded.sb", naming: "/Library/Application Support/SNLUOverrides.sqlite"),
        "SNLUOverrides.sqlite-shm": .file("/System/Library/Sandbox/Profiles/com.apple.assistantd.transcoded.sb", naming: "/Library/Application Support/SNLUOverrides.sqlite-shm"),
        "SNLUOverrides.sqlite-wal": .file("/System/Library/Sandbox/Profiles/com.apple.assistantd.transcoded.sb", naming: "/Library/Application Support/SNLUOverrides.sqlite-wal"),
        "SubmitDiagInfo": .file("/System/Library/Frameworks/OpenGL.framework/Versions/A/Libraries/DumpGPURestart", naming: "Library/Application Support/SubmitDiagInfo"),
        "SyncServices": .file("/System/Library/Sandbox/Profiles/com.apple.suggestd.sb", naming: "/Library/Application Support/SyncServices"),
        "transparencyd": .file("/System/Library/Sandbox/Profiles/com.apple.swtransparencyd.sb", naming: "/Library/Application Support/transparencyd"),
        "videosubscriptionsd": .file("/System/Library/Sandbox/Profiles/com.apple.videosubscriptionsd.sb", naming: "/Library/Application Support/videosubscriptionsd"),
        "voicememod": .file("/System/iOSSupport/System/Library/PrivateFrameworks/VoiceMemos.framework/Support/voicememod", naming: "Library/Application Support/voicememod"),
        "XCTest": .file("/usr/libexec/testmanagerd", naming: "Library/Application Support/XCTest"),
    ]

    static let caches: [String: Proof] = [
        "AAProfilePicture_*.png": .image("/System/Library/PrivateFrameworks/AOSUI.framework/Versions/A/AOSUI", naming: "AAProfilePicture_%@.png"),
        "AMSDataMigratorTool": .part("/System/Library/PrivateFrameworks/AppleMediaServices.framework/Versions/A/Resources/AMSDataMigratorTool"),
        "amsengagementd": .file("/System/Library/Sandbox/Profiles/com.apple.amsengagementd.sb", naming: "/Library/Caches/amsengagementd"),
        "amsondevicestoraged": .part("/System/Library/PrivateFrameworks/OnDeviceStorage.framework/Support/amsondevicestoraged"),
        "assessmentagent": .part("/usr/libexec/assessmentagent"),
        "AudioComponentRegistrar": .part("/System/Library/Frameworks/AudioToolbox.framework/AudioComponentRegistrar"),
        "AudioConverterService": .part("/System/Library/Frameworks/AudioToolbox.framework/XPCServices/AudioConverterService.xpc"),
        "betaenrollmentagent": .part("/usr/libexec/betaenrollmentagent"),
        "Cleanup At Startup": .file("/System/Library/Sandbox/Profiles/com.apple.sharingd.sb", naming: "/Library/Caches/Cleanup At Startup"),
        "CloudKit": .part("/System/Library/Frameworks/CloudKit.framework"),
        "ColorSync": .part("/System/Library/ColorSync"),
        "CommCenter": .file("/usr/share/sandbox/com.apple.CommCenter.sb", naming: "/Library/Caches/CommCenter"),
        "commerce": .file("/System/Library/Sandbox/Profiles/com.apple.CommerceKit.TransactionService.sb", naming: "/Library/Caches/commerce"),
        "Configuration": .file("/System/Library/Sandbox/Profiles/com.apple.maps.destinationd.sb", naming: "/Library/Caches/Configuration"),
        "containermanagerd": .part("/usr/libexec/containermanagerd"),
        "contentlinkingd": .part("/System/Library/PrivateFrameworks/Synapse.framework/Support/contentlinkingd"),
        "ContextStoreAgent": .file("/System/Library/Sandbox/Profiles/com.apple.ContextStoreAgent.sb", naming: "/Library/Caches/ContextStoreAgent"),
        "CoreSpeech": .file("/System/Library/Sandbox/Profiles/com.apple.corespeechd.sb", naming: "/Library/Caches/CoreSpeech"),
        "CrashHandlerService": .part("/System/Library/Sandbox/Profiles/com.apple.audio.CrashHandlerService.sb"),
        "CSExattrCryptoService": .part("/System/Library/PrivateFrameworks/CSExattrCrypto.framework/Versions/A/XPCServices/CSExattrCryptoService.xpc"),
        "Desktop Pictures": .part("/System/Library/Desktop Pictures"),
        "destinationd": .file("/System/Library/Sandbox/Profiles/com.apple.maps.destinationd.sb", naming: "/Library/Caches/destinationd"),
        "diagnosticextensionsd": .part("/usr/libexec/diagnosticextensionsd"),
        "duetexpertd": .part("/usr/libexec/duetexpertd"),
        "EnergyKit": .file("/System/Library/Sandbox/Profiles/com.apple.EnergyKitService.sb", naming: "/Library/Caches/EnergyKit"),
        "FamilyCircle": .part("/System/Library/PrivateFrameworks/FamilyCircle.framework"),
        "familycircled": .part("/System/Library/PrivateFrameworks/FamilyCircle.framework/Versions/A/Resources/familycircled"),
        "Finance": .file("/System/Library/Sandbox/Profiles/com.apple.financed.sb", naming: "/Library/Caches/Finance"),
        "gamed": .part("/usr/libexec/gamed"),
        "GameKit": .part("/System/Library/Frameworks/GameKit.framework"),
        "GameStoreKit": .part("/System/Library/PrivateFrameworks/GameStoreKit.framework"),
        "GeoServices": .part("/System/Library/PrivateFrameworks/GeoServices.framework"),
        "heard": .part("/System/Library/PrivateFrameworks/HearingCore.framework/heard"),
        "homed": .part("/System/Library/PrivateFrameworks/HomeKitDaemon.framework/Support/homed"),
        "HomeKit": .part("/System/Library/Frameworks/HomeKit.framework"),
        "icdd": .part("/System/Library/Image Capture/Support/icdd"),
        "itunescloudd": .part("/System/Library/PrivateFrameworks/iTunesCloud.framework/Support/itunescloudd"),
        "JetPackCache": .file("/System/Library/Sandbox/Profiles/com.apple.GameOverlayUI.sb", naming: "/Library/Caches/JetPackCache"),
        "knowledge-agent": .file("/System/Library/Sandbox/Profiles/com.apple.knowledge-agent.sb", naming: "/Library/Caches/knowledge-agent"),
        "locationd": .file("/usr/libexec/sysdiagnosed", naming: "Library/Caches/locationd"),
        "mapspushd": .file("/System/Library/Sandbox/Profiles/com.apple.mapspushd.sb", naming: "/Library/Caches/mapspushd"),
        "mbuseragent": .part("/System/Library/CoreServices/Setup Assistant.app/Contents/Resources/mbuseragent"),
        "mediaanalysisd-access": .part("/System/Library/PrivateFrameworks/MediaAnalysisAccess.framework/Versions/A/XPCServices/mediaanalysisd-access.xpc"),
        "metrickitd": .part("/usr/libexec/metrickitd"),
        "Metrics": .file("/System/Library/Sandbox/Profiles/com.apple.gamed.sb", naming: "/Library/Caches/Metrics"),
        "MobileActivation": .file("/System/Library/Sandbox/Profiles/mobileactivationd.sb", naming: "/Library/Caches/MobileActivation"),
        "mobileactivationd": .file("/System/Library/Sandbox/Profiles/mobileactivationd.sb", naming: "/Library/Caches/mobileactivationd"),
        "mobileassetd": .file("/usr/share/sandbox/com.apple.mobileassetd.sb", naming: "/Library/Caches/mobileassetd"),
        "mobiletimerd": .part("/System/Library/PrivateFrameworks/MobileTimer.framework/Executables/mobiletimerd"),
        "nbagent": .through(26, .file("/System/Library/Sandbox/Profiles/com.apple.noticeboard.agent.sb", naming: "/Library/Caches/nbagent")),
        "OnDemandResources": .file("/System/Library/Sandbox/Profiles/com.apple.AppStoreDaemon.StorePrivilegedODRService.sb", naming: "/Library/Caches/OnDemandResources"),
        "OnDeviceStorage": .file("/System/Library/Sandbox/Profiles/com.apple.amsondevicestoraged.sb", naming: "/Library/Caches/OnDeviceStorage"),
        "PassKit": .part("/System/Library/Frameworks/PassKit.framework"),
        "proactived": .part("/usr/libexec/proactived"),
        "ptpcamerad": .part("/usr/libexec/ptpcamerad"),
        "rtcreportingd": .file("/System/Library/Sandbox/Profiles/com.apple.rtcreportingd.sb", naming: "/Library/Caches/rtcreportingd"),
        "SandboxHelper": .part("/System/Library/Sandbox/Profiles/com.apple.audio.SandboxHelper.sb"),
        "SiriTTS": .file("/System/Library/Sandbox/Profiles/com.apple.SiriTTSTrainingAgent.sb", naming: "/Library/Caches/SiriTTS"),
        "sportsd": .file("/System/Library/Sandbox/Profiles/com.apple.sportsd.sb", naming: "/Library/Caches/sportsd"),
        "ssu": .file("/System/Library/Sandbox/Profiles/com.apple.assistant_cdmd.sb", naming: "/Library/Caches/ssu"),
        "StatusKitAgent": .part("/System/Library/PrivateFrameworks/StatusKit.framework/StatusKitAgent"),
        "storeaccountd": .file("/System/Library/Sandbox/Profiles/com.apple.storeaccountd.sb", naming: "/Library/Caches/storeaccountd"),
        "storeassetd": .file("/System/Library/Sandbox/Profiles/com.apple.storeassetd.sb", naming: "/Library/Caches/storeassetd"),
        "storedownloadd": .file("/System/Library/Sandbox/Profiles/com.apple.storedownloadd.sb", naming: "/Library/Caches/storedownloadd"),
        "storelegacy": .file("/System/Library/Sandbox/Profiles/com.apple.storelegacy.sb", naming: "/Library/Caches/storelegacy"),
        "storeuid": .file("/System/Library/Sandbox/Profiles/com.apple.storeuid.sb", naming: "/Library/Caches/storeuid"),
        "studentd": .part("/usr/libexec/studentd"),
        "SubmitDiagInfo": .file("/System/Library/Sandbox/Profiles/com.apple.SubmitDiagInfo.sb", naming: "/Library/Caches/SubmitDiagInfo"),
        "talagent": .part("/System/Library/CoreServices/talagent"),
        "TTSResourceCache.plist": .file("/System/Library/Sandbox/Profiles/com.apple.accessibility.LiveTranscriptionAgent.sb", naming: "/Library/Caches/TTSResourceCache.plist"),
        "VoiceTrigger": .file("/System/Library/Sandbox/Profiles/com.apple.assistantd.sb", naming: "/Library/Caches/VoiceTrigger"),
        "watchlistd": .part("/System/Library/PrivateFrameworks/WatchListKit.framework/Support/watchlistd"),
    ]

    static let logs: [String: Proof] = [
        "Accounts": .file("/System/Library/Sandbox/Profiles/frameworks.sb", naming: "/Library/Logs/Accounts"),
        "AppleSSE.log": .file("/System/Library/Sandbox/Profiles/com.apple.passd.sb", naming: "/Library/Logs/AppleSSE.log"),
        "AppleSupport": .file("/System/Library/CoreServices/Setup Assistant.app/Contents/MacOS/Setup Assistant", naming: "Library/Logs/AppleSupport"),
        "Assistant": .file("/System/Library/Sandbox/Profiles/com.apple.assistantd.sb", naming: "/Library/Logs/Assistant"),
        "ats.log": .file("/System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/ATS.framework/Versions/A/Resources/libATSServer.dylib", naming: "Library/Logs/ats.log"),
        "AutoBugCapture": .file("/System/Library/PrivateFrameworks/CacheDelete.framework/deleted_helper", naming: "Library/Logs/AutoBugCapture"),
        "Baseband": .file("/System/Library/Frameworks/CoreTelephony.framework/Support/CommCenter", naming: "Library/Logs/Baseband"),
        "BioLog": .file("/usr/libexec/biometrickitd", naming: "Library/Logs/BioLog"),
        "Bluetooth": .file("/usr/share/sandbox/bluetoothd.sb", naming: "/Library/Logs/Bluetooth"),
        "CallHistory": .file("/System/Library/Sandbox/Profiles/com.apple.assistantd.transcoded.sb", naming: "/Library/Logs/CallHistory"),
        "CoreCapture": .file("/usr/libexec/wifivelocityd", naming: "Library/Logs/CoreCapture"),
        "CoreStorage.log": .file("/System/Library/Filesystems/apfs.fs/Contents/Resources/apfs_preflight_converter", naming: "Library/Logs/CoreStorage.log"),
        "CoreTelephonyTrace": .through(26, .file("/System/Library/Frameworks/CoreTelephony.framework/Support/CommCenter", naming: "Library/Logs/CoreTelephonyTrace")),
        "CoreTelephonyTraceScratch": .through(26, .file("/System/Library/Frameworks/CoreTelephony.framework/Support/CommCenter", naming: "Library/Logs/CoreTelephonyTraceScratch")),
        "CrashReporter": .file("/usr/libexec/DumpPanic", naming: "/Library/Logs/CrashReporter"),
        "DiagnosticReports": .file("/System/Library/CoreServices/SubmitDiagInfo", naming: "Library/Logs/DiagnosticReports"),
        "DiscRecording.log": .file("/System/Library/SystemProfiler/SPLogsReporter.spreporter/Contents/MacOS/SPLogsReporter", naming: "Library/Logs/DiscRecording.log"),
        "findmydeviced": .file("/usr/libexec/findmydeviced", naming: "Library/Logs/findmydeviced"),
        "fsck_apfs.log": .file("/System/Library/Filesystems/apfs.fs/Contents/Resources/fsck_apfs", naming: "Library/Logs/fsck_apfs.log"),
        "fsck_hfs.log": .file("/System/Library/Filesystems/hfs.fs/Contents/Resources/fsck_hfs", naming: "Library/Logs/fsck_hfs.log"),
        "hidfw-crashlogs": .file("/usr/libexec/sysdiagnosed", naming: "/Library/Logs/hidfw-crashlogs"),
        "intelligentroutingd": .file("/System/Library/Sandbox/Profiles/com.apple.intelligentroutingd.sb", naming: "/Library/Logs/intelligentroutingd"),
        "InternetAccounts": .file("/System/Library/Sandbox/Profiles/frameworks.sb", naming: "/Library/Logs/InternetAccounts"),
        "IOKit": .file("/System/Library/CoreServices/powerd.bundle/powerd", naming: "Library/Logs/IOKit"),
        "khwm.log": .through(26, .file("/usr/libexec/sysstatuscheck", naming: "Library/Logs/khwm.log")),
        "LKDC-setup.log": .file("/usr/libexec/configureLocalKDC", naming: "/Library/Logs/LKDC-setup.log"),
        "ManagedClient": .file("/System/Library/CoreServices/SecurityAgentPlugins/MCXMechanism.bundle/Contents/MacOS/MCXMechanism", naming: "Library/Logs/ManagedClient"),
        "MCXTools.log": .file("/usr/libexec/mcxalr", naming: "/Library/Logs/MCXTools.log"),
        "MDM": .file("/System/Library/ExtensionKit/Extensions/ProfilesSettingsExt.appex/Contents/MacOS/ProfilesSettingsExt", naming: "Library/Logs/MDM"),
        "MDMSim": .file("/usr/libexec/mdmclient", naming: "Library/Logs/MDMSim"),
        "mdworker": .through(26, .file("/usr/share/sandbox/mdworker-mail.sb", naming: "/Library/Logs/mdworker")),
        "Metal": .file("/System/Library/Sandbox/Profiles/com.apple.mtlcompilerservice.sb", naming: "/Library/Logs/Metal"),
        "milod": .file("/System/Library/Sandbox/Profiles/com.apple.milod.sb", naming: "/Library/Logs/milod"),
        "mobileactivationd": .file("/usr/libexec/mobileactivationd", naming: "Library/Logs/mobileactivationd"),
        "MobileInstallation": .part("/System/Library/PrivateFrameworks/MobileInstallation.framework"),
        "PasswordService": .file("/usr/sbin/PasswordService", naming: "Library/Logs/PasswordService"),
        "PersonalizationPortrait": .file("/System/Library/Sandbox/Profiles/com.apple.suggestd.sb", naming: "/Library/Logs/PersonalizationPortrait"),
        "PhotosLegacyUpgrade.aapbz": .file("/System/Library/PrivateFrameworks/CloudPhotoLibrary.framework/Versions/A/XPCServices/com.apple.Photos.CPLDiagnose.xpc/Contents/MacOS/com.apple.Photos.CPLDiagnose", naming: "Library/Logs/PhotosLegacyUpgrade.aapbz"),
        "PhotosLegacyUpgradeCompanion.aapbz": .file("/System/Library/PrivateFrameworks/CloudPhotoLibrary.framework/Versions/A/XPCServices/com.apple.Photos.CPLDiagnose.xpc/Contents/MacOS/com.apple.Photos.CPLDiagnose", naming: "Library/Logs/PhotosLegacyUpgradeCompanion.aapbz"),
        "photoslibraryupgrade.log": .file("/System/Library/PrivateFrameworks/PhotoLibraryServicesCore.framework/Versions/A/XPCServices/com.apple.Photos.Migration.xpc/Contents/MacOS/com.apple.Photos.Migration", naming: "Library/Logs/photoslibraryupgrade.log"),
        "PhotosSearch.aapbz": .file("/System/Library/PrivateFrameworks/CloudPhotoLibrary.framework/Versions/A/XPCServices/com.apple.Photos.CPLDiagnose.xpc/Contents/MacOS/com.apple.Photos.CPLDiagnose", naming: "Library/Logs/PhotosSearch.aapbz"),
        "PhotosUpgrade.aapbz": .file("/System/Library/PrivateFrameworks/CloudPhotoLibrary.framework/Versions/A/XPCServices/com.apple.Photos.CPLDiagnose.xpc/Contents/MacOS/com.apple.Photos.CPLDiagnose", naming: "Library/Logs/PhotosUpgrade.aapbz"),
        "PhotosUpgrade.log": .file("/System/Library/PrivateFrameworks/CloudPhotoLibrary.framework/Versions/A/XPCServices/com.apple.Photos.CPLDiagnose.xpc/Contents/MacOS/com.apple.Photos.CPLDiagnose", naming: "Library/Logs/PhotosUpgrade.log"),
        "PhotosUpgradeCompanion.log": .file("/System/Library/PrivateFrameworks/CloudPhotoLibrary.framework/Versions/A/XPCServices/com.apple.Photos.CPLDiagnose.xpc/Contents/MacOS/com.apple.Photos.CPLDiagnose", naming: "Library/Logs/PhotosUpgradeCompanion.log"),
        "pipelined": .file("/usr/libexec/locationd", naming: "Library/Logs/pipelined"),
        "PrivacyPreservingMeasurement": .file("/System/Library/Sandbox/Profiles/com.apple.dprivacyd.agent.sb", naming: "/Library/Logs/PrivacyPreservingMeasurement"),
        "ProtectedCloudStorage.log": .file("/usr/share/sandbox/com.apple.cloudd.sb", naming: "/Library/Logs/ProtectedCloudStorage.log"),
        "recoverylogd": .part("/System/Library/Sandbox/Profiles/recoverylogd.sb"),
        "RTCReporting": .file("/System/Library/PrivateFrameworks/AVConference.framework/PlugIns/com.apple.AVConference.Diagnostic.appex/Contents/MacOS/com.apple.AVConference.Diagnostic", naming: "Library/Logs/RTCReporting"),
        "RTCReports": .file("/System/Library/Sandbox/Profiles/com.apple.rtcreportingd.sb", naming: "/Library/Logs/RTCReports"),
        "SiriTTSService": .file("/System/Library/Sandbox/Profiles/com.apple.sirittsd.sb", naming: "/Library/Logs/SiriTTSService"),
        "SiriTTSTrainer": .file("/System/Library/Sandbox/Profiles/com.apple.SiriTTSTrainingAgent.sb", naming: "/Library/Logs/SiriTTSTrainer"),
        "slapconfig.log": .file("/usr/sbin/slapconfig", naming: "Library/Logs/slapconfig.log"),
        "SMSMigrator": .file("/System/Library/Sandbox/Profiles/com.apple.imdpersistence.IMDPersistenceAgent.sb", naming: "/Library/Logs/SMSMigrator"),
        "Software Update.log": .file("/System/Library/SystemProfiler/SPLogsReporter.spreporter/Contents/MacOS/SPLogsReporter", naming: "Library/Logs/Software Update.log"),
        "Touch": .file("/System/Library/HIDPlugins/ServicePlugins/HSTouchHIDService.plugin/Contents/MacOS/HSTouchHIDService", naming: "Library/Logs/Touch"),
        "Trial": .file("/System/Library/Sandbox/Profiles/com.apple.triald.sb", naming: "/Library/Logs/Trial"),
        "Ubiquity": .file("/System/Library/Sandbox/Profiles/com.apple.bird.sb", naming: "/Library/Logs/Ubiquity"),
        "vinylscratch": .through(26, .file("/System/Library/Frameworks/CoreTelephony.framework/Support/CommCenter", naming: "Library/Logs/vinylscratch")),
        "VoiceTrigger": .file("/System/Library/Sandbox/Profiles/com.apple.corespeechd.sb", naming: "/Library/Logs/VoiceTrigger"),
        "WebDAVFileSharing.log": .file("/usr/libexec/wfs/webdavsharing_mapper", naming: "Library/Logs/WebDAVFileSharing.log"),
        "WindowServer": .file("/usr/libexec/sysdiagnosed", naming: "/Library/Logs/WindowServer"),
        "Xsan": .file("/System/Library/Filesystems/acfs.fs/Contents/Resources/acfs.util", naming: "/Library/Logs/Xsan"),
    ]

    static let preferences: [String: Proof] = [
        "analyticsd.plist": .file("/System/Library/Sandbox/Profiles/com.apple.analyticsd.sb", naming: "/Library/Preferences/analyticsd.plist"),
        "Audio": .file("/System/Library/Sandbox/Profiles/com.apple.audio.coreaudiod.sb", naming: "/Library/Preferences/Audio"),
        "Bluetooth": .file("/usr/sbin/bluetoothd", naming: "Library/Preferences/Bluetooth"),
        "CD Info.cidb": .file("/System/Library/Filesystems/cddafs.fs/Contents/Resources/mount_cddafs", naming: "Library/Preferences/CD Info.cidb"),
        "ContextStoreAgent.plist": .file("/System/Library/Sandbox/Profiles/com.apple.ContextStoreAgent.sb", naming: "/Library/Preferences/ContextStoreAgent.plist"),
        "csidata": .file("/System/Library/Frameworks/CoreTelephony.framework/Support/CommCenter", naming: "Library/Preferences/csidata"),
        "diagnostics_agent.plist": .part("/System/Library/CoreServices/diagnostics_agent"),
        "DirectoryService": .file("/System/Library/Frameworks/OpenDirectory.framework/odmigrationtool", naming: "Library/Preferences/DirectoryService"),
        "familycircled.plist": .part("/System/Library/PrivateFrameworks/FamilyCircle.framework/Versions/A/Resources/familycircled"),
        "FeatureFlags": .file("/usr/libexec/init_featureflags", naming: "Library/Preferences/FeatureFlags"),
        "GeoServices": .part("/System/Library/PrivateFrameworks/GeoServices.framework"),
        "knowledge-agent.plist": .file("/System/Library/Sandbox/Profiles/com.apple.knowledge-agent.sb", naming: "/Library/Preferences/knowledge-agent.plist"),
        "Logging": .file("/usr/libexec/sysdiagnosed", naming: "Library/Preferences/Logging"),
        "loginwindow.plist": .part("/System/Library/CoreServices/loginwindow.app"),
        "mbuseragent.plist": .part("/System/Library/CoreServices/Setup Assistant.app/Contents/Resources/mbuseragent"),
        "mdworker.plist": .file("/usr/share/sandbox/mdworker.sb", naming: "/Library/Preferences/mdworker.plist"),
        "MobileMeAccounts.plist": .file("/System/Library/Sandbox/Profiles/frameworks.sb", naming: "(preference-domain \"MobileMeAccounts\")"),
        "networkserviceproxy.plist": .file("/System/Library/Sandbox/Profiles/com.apple.networkserviceproxy.sb", naming: "/Library/Preferences/networkserviceproxy.plist"),
        "nfcd.plist": .file("/System/Library/Sandbox/Profiles/nfcd.sb", naming: "/Library/Preferences/nfcd.plist"),
        "no_backup": .file("/System/Library/Frameworks/CoreTelephony.framework/Support/CommCenter", naming: "no_backup/commcenter_runtime_storage"),
        "OpenDirectory": .file("/usr/libexec/opendirectoryd", naming: "/Library/Preferences/OpenDirectory/"),
        "opendirectoryd.plist": .through(26, .file("/System/Library/Sandbox/Profiles/com.apple.opendirectoryd-deny-default.sb", naming: "/Library/Preferences/opendirectoryd.plist")),
        "pbs.plist": .part("/System/Library/CoreServices/pbs"),
        "ProtectedCloudStorage": .part("/System/Library/PrivateFrameworks/ProtectedCloudStorage.framework"),
        "rtcreportingd.plist": .file("/System/Library/Sandbox/Profiles/com.apple.rtcreportingd.sb", naming: "/Library/Preferences/rtcreportingd.plist"),
        "sharedfilelistd.plist": .part("/System/Library/CoreServices/sharedfilelistd"),
        "SystemConfiguration": .file("/usr/libexec/sysdiagnosed", naming: "Library/Preferences/SystemConfiguration"),
        "TokenBucketRateLimiter.plist": .image("/System/Library/PrivateFrameworks/SpotlightKnowledgeDaemon.framework/Versions/A/SpotlightKnowledgeDaemon", naming: "TokenBucketRateLimiter"),
        "Xsan": .file("/System/Library/ConfigurationProfiles/PlugIns/xsanplugin.profileDomainPlugin/Contents/MacOS/xsanplugin", naming: "Library/Preferences/Xsan"),
    ]

    static let webKit: [String: Proof] = [
        "Databases": .image("/System/Library/Frameworks/WebKit.framework/Versions/A/Frameworks/WebKitLegacy.framework/Versions/A/WebKitLegacy", naming: "~/Library/WebKit/Databases"),
        "JavaScriptCoreDebug": .image("/System/Library/PrivateFrameworks/Safari.framework/Versions/A/Safari", naming: "~/Library/WebKit/JavaScriptCoreDebug"),
        "LocalStorage": .image("/System/Library/PrivateFrameworks/SafariSharedUI.framework/Versions/A/SafariSharedUI", naming: "~/Library/WebKit/LocalStorage"),
        "MediaKeys": .image("/System/Library/Frameworks/WebKit.framework/Versions/A/Frameworks/WebKitLegacy.framework/Versions/A/WebKitLegacy", naming: "~/Library/WebKit/MediaKeys"),
    ]

    static let cookies: [String: Proof] = [
        "Cookies.binarycookies": .image("/System/Library/Frameworks/WebKit.framework/Versions/A/WebKit", naming: "Cookies.binarycookies"),
    ]

    /// Whether macOS keeps an item called `fileName` for its own services in a folder of `kind`. A process keeps its
    /// caches, its HTTP storage and its temporary items under the same name.
    static func keeps(_ fileName: String, in kind: SearchLocation.Kind) -> Bool {
        let names = switch kind {
        case .applicationSupport: applicationSupportNames
        case .caches, .httpStorages, .temporaryItems: cachesNames
        case .logs: logsNames
        case .preferences: preferencesNames
        case .webKit: webKitNames
        case .cookies: cookiesNames
        default: noNames
        }
        return names.hold(fileName)
    }

    private static let applicationSupportNames = Names(applicationSupport)
    private static let cachesNames = Names(caches)
    private static let logsNames = Names(logs)
    private static let preferencesNames = Names(preferences)
    private static let webKitNames = Names(webKit)
    private static let cookiesNames = Names(cookies)
    private static let noNames = Names([:])

    /// The names of one list, lowercased, those with a `*` read as patterns.
    private struct Names {
        let exact: Set<String>
        let patterns: [String]

        init(_ list: [String: Proof]) {
            let names = list.keys.map { $0.lowercased() }
            exact = Set(names.filter { !$0.contains("*") })
            patterns = names.filter { $0.contains("*") }
        }

        func hold(_ name: String) -> Bool {
            let name = name.lowercased()
            return exact.contains(name) || patterns.contains { fnmatch($0, name, 0) == 0 }
        }
    }
}

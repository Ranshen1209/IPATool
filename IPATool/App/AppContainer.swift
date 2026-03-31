import Foundation

@MainActor
final class AppContainer {
    let settings: AppSettingsController
    let keychainStore: KeychainCredentialStore
    let httpClient: HTTPClient
    let authService: AuthServicing
    let catalogService: AppCatalogServicing
    let purchaseService: PurchaseServicing
    let downloadService: DownloadServicing
    let logStore: AppLogger
    let downloadManager: ChunkedDownloadManager
    let ipaProcessor: IPAProcessingServicing
    let sandboxAccessCoordinator: SandboxAccessCoordinator
    let loadCachedCredentialUseCase: LoadCachedCredentialUseCase
    let loginUseCase: LoginUseCase
    let searchAppUseCase: SearchAppUseCase
    let requestLicenseUseCase: RequestLicenseUseCase
    let createDownloadTaskUseCase: CreateDownloadTaskUseCase

    convenience init() {
        let settingsStore = UserDefaultsAppSettingsStore()
        let bookmarkStore = UserDefaultsSandboxBookmarkStore()
        let settings = AppSettingsController(
            snapshot: settingsStore.load(),
            store: settingsStore,
            bookmarkStore: bookmarkStore
        )
        let keychainStore = KeychainCredentialStore()
        let sessionConfiguration = URLSessionConfiguration.default
        sessionConfiguration.httpShouldSetCookies = true
        sessionConfiguration.httpCookieAcceptPolicy = .always
        sessionConfiguration.httpCookieStorage = .shared
        sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: sessionConfiguration)
        let httpClient = URLSessionHTTPClient(session: session)
        let sandboxAccessCoordinator = SandboxAccessCoordinator()
        let logStore = AppLogger(
            seedEntries: [
                LogEntry(level: .info, category: "app", message: "Application container initialized."),
                LogEntry(level: .notice, category: "architecture", message: "Apple login, catalog lookup, and purchase flows are wired through isolated private protocol adapters.")
            ]
        )
        let authGateway = PendingAppleAuthenticationGateway(httpClient: httpClient)
        let catalogGateway = PendingAppleCatalogGateway(httpClient: httpClient)
        let purchaseGateway = PendingApplePurchaseGateway(httpClient: httpClient)
        let authService = AppleAuthRepository(
            gateway: authGateway,
            keychainStore: keychainStore,
            logger: logStore
        )
        let catalogService = AppleCatalogRepository(
            gateway: catalogGateway,
            httpClient: httpClient,
            logger: logStore
        )
        let purchaseService = ApplePurchaseRepository(
            gateway: purchaseGateway,
            logger: logStore
        )
        let ipaProcessor = IPAProcessingRepository(
            verifier: FileIntegrityVerifier(),
            archiveRewriter: IPAArchiveRewriter(),
            logger: logStore
        )
        let downloadManager = ChunkedDownloadManager(
            persistenceURL: URL(fileURLWithPath: (settings.cacheDirectoryPath as NSString).expandingTildeInPath)
                .appendingPathComponent("tasks.json"),
            httpClient: httpClient,
            logger: logStore,
            credentialStore: keychainStore,
            ipaProcessor: ipaProcessor
        )
        let downloadService = ChunkedDownloadRepository(manager: downloadManager)
        let loadCachedCredentialUseCase = LoadCachedCredentialUseCase(
            keychainStore: keychainStore,
            logger: logStore
        )
        let loginUseCase = LoginUseCase(
            authService: authService,
            logger: logStore
        )
        let searchAppUseCase = SearchAppUseCase(
            catalogService: catalogService,
            logger: logStore
        )
        let requestLicenseUseCase = RequestLicenseUseCase(
            purchaseService: purchaseService,
            logger: logStore
        )
        let createDownloadTaskUseCase = CreateDownloadTaskUseCase(
            downloadService: downloadService,
            logger: logStore
        )

        self.init(
            settings: settings,
            keychainStore: keychainStore,
            httpClient: httpClient,
            authService: authService,
            catalogService: catalogService,
            purchaseService: purchaseService,
            downloadService: downloadService,
            logStore: logStore,
            downloadManager: downloadManager,
            ipaProcessor: ipaProcessor,
            sandboxAccessCoordinator: sandboxAccessCoordinator,
            loadCachedCredentialUseCase: loadCachedCredentialUseCase,
            loginUseCase: loginUseCase,
            searchAppUseCase: searchAppUseCase,
            requestLicenseUseCase: requestLicenseUseCase,
            createDownloadTaskUseCase: createDownloadTaskUseCase
        )
    }

    init(
        settings: AppSettingsController,
        keychainStore: KeychainCredentialStore,
        httpClient: HTTPClient,
        authService: AuthServicing,
        catalogService: AppCatalogServicing,
        purchaseService: PurchaseServicing,
        downloadService: DownloadServicing,
        logStore: AppLogger,
        downloadManager: ChunkedDownloadManager,
        ipaProcessor: IPAProcessingServicing,
        sandboxAccessCoordinator: SandboxAccessCoordinator,
        loadCachedCredentialUseCase: LoadCachedCredentialUseCase,
        loginUseCase: LoginUseCase,
        searchAppUseCase: SearchAppUseCase,
        requestLicenseUseCase: RequestLicenseUseCase,
        createDownloadTaskUseCase: CreateDownloadTaskUseCase
    ) {
        self.settings = settings
        self.keychainStore = keychainStore
        self.httpClient = httpClient
        self.authService = authService
        self.catalogService = catalogService
        self.purchaseService = purchaseService
        self.downloadService = downloadService
        self.logStore = logStore
        self.downloadManager = downloadManager
        self.ipaProcessor = ipaProcessor
        self.sandboxAccessCoordinator = sandboxAccessCoordinator
        self.loadCachedCredentialUseCase = loadCachedCredentialUseCase
        self.loginUseCase = loginUseCase
        self.searchAppUseCase = searchAppUseCase
        self.requestLicenseUseCase = requestLicenseUseCase
        self.createDownloadTaskUseCase = createDownloadTaskUseCase
    }
}

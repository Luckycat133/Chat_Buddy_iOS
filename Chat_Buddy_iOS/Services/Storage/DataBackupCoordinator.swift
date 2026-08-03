import Foundation

/// Facade that wires together `DataExporter` and `DataImporter` with the
/// managers and stores they require.
///
/// Created once at the app root with all dependencies, then injected into the
/// environment so `ExportImportView` (and any other backup UI) only needs to
/// read a single `@Environment(DataBackupCoordinator.self)` instead of 15
/// separate environment objects.
@Observable final class DataBackupCoordinator {
    private let configStore: APIConfigStore
    private let localization: LocalizationManager
    private let themeManager: ThemeManager
    private let accentColorManager: AccentColorManager
    private let appState: AppState
    private let stores: [any StoreReloading]

    init(
        configStore: APIConfigStore,
        localization: LocalizationManager,
        themeManager: ThemeManager,
        accentColorManager: AccentColorManager,
        appState: AppState,
        stores: [any StoreReloading]
    ) {
        self.configStore = configStore
        self.localization = localization
        self.themeManager = themeManager
        self.accentColorManager = accentColorManager
        self.appState = appState
        self.stores = stores
    }

    /// Encodes the full app backup (storage, moments images, API config, settings).
    func exportData(includeSensitiveData: Bool) throws -> Data {
        try DataExporter.exportToData(
            configStore: configStore,
            includeSensitiveData: includeSensitiveData
        )
    }

    /// Imports a backup blob, applying it to all wired managers and reloading stores.
    /// Returns the number of items restored.
    @discardableResult
    func importBackup(from data: Data) throws -> Int {
        try DataImporter.importBackup(
            from: data,
            configStore: configStore,
            localization: localization,
            themeManager: themeManager,
            accentColorManager: accentColorManager,
            appState: appState,
            stores: stores
        )
    }
}

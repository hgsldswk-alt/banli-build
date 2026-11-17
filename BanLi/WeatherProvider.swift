import CoreLocation
import Foundation
import WeatherKit

@MainActor
final class WeatherProvider: NSObject, CLLocationManagerDelegate {
    static let shared = WeatherProvider()

    private let manager = CLLocationManager()
    private var locationWaiters: [CheckedContinuation<CLLocation?, Never>] = []
    private var authWaiters: [CheckedContinuation<Void, Never>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var authorization: CLAuthorizationStatus { manager.authorizationStatus }

    func requestPermission() async -> Bool {
        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { c in
                authWaiters.append(c)
                manager.requestWhenInUseAuthorization()
            }
        }
        let s = manager.authorizationStatus
        return s == .authorizedWhenInUse || s == .authorizedAlways
    }

    func refreshIfNeeded(force: Bool = false) async -> WeatherSnapshot? {
        let cached = WeatherCache.load()
        guard WeatherCache.enabled else { return cached }
        if !force, let cached, cached.isFresh() { return cached }
        let s = manager.authorizationStatus
        guard s == .authorizedWhenInUse || s == .authorizedAlways else { return cached }
        guard let location = await currentLocation() else { return cached }

        do {
            let service = WeatherService.shared
            let (hourly, daily) = try await service.weather(for: location, including: .hourly, .daily)
            let attribution = try? await service.attribution
            let hours = hourly.forecast.prefix(48).map {
                WeatherSnapshot.Hour(
                    date: $0.date,
                    temperature: $0.temperature.converted(to: .celsius).value,
                    precipitationChance: $0.precipitationChance,
                    symbol: $0.symbolName,
                    condition: $0.condition.description
                )
            }
            let days = daily.forecast.prefix(7).map {
                WeatherSnapshot.Day(
                    date: $0.date,
                    high: $0.highTemperature.converted(to: .celsius).value,
                    low: $0.lowTemperature.converted(to: .celsius).value,
                    precipitationChance: $0.precipitationChance,
                    symbol: $0.symbolName,
                    condition: $0.condition.description
                )
            }
            let place = await placeName(for: location)
            let snap = WeatherSnapshot(
                hours: Array(hours), days: Array(days), fetchedAt: Date(), place: place,
                markLightURL: attribution?.combinedMarkLightURL,
                markDarkURL: attribution?.combinedMarkDarkURL,
                legalURL: attribution?.legalPageURL
            )
            WeatherCache.save(snap)
            return snap
        } catch {
            return cached
        }
    }

    private func placeName(for location: CLLocation) async -> String? {
        let marks = try? await CLGeocoder().reverseGeocodeLocation(location, preferredLocale: .current)
        let m = marks?.first
        return m?.subLocality ?? m?.locality ?? m?.administrativeArea
    }

    private func currentLocation() async -> CLLocation? {
        if let last = manager.location, Date().timeIntervalSince(last.timestamp) < 30 * 60 {
            return last
        }
        return await withCheckedContinuation { c in
            locationWaiters.append(c)
            if locationWaiters.count == 1 { manager.requestLocation() }
        }
    }


    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard manager.authorizationStatus != .notDetermined else { return }
            let waiters = self.authWaiters
            self.authWaiters = []
            waiters.forEach { $0.resume() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let loc = locations.last
        Task { @MainActor in self.finishLocation(loc) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finishLocation(nil) }
    }

    private func finishLocation(_ loc: CLLocation?) {
        let waiters = locationWaiters
        locationWaiters = []
        waiters.forEach { $0.resume(returning: loc) }
    }
}

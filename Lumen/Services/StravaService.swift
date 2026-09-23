import Foundation
import AuthenticationServices
import SwiftUI

@MainActor
public final class StravaService: ObservableObject {
    public static let shared = StravaService()

    public var clientID = "YOUR_STRAVA_CLIENT_ID"
    public var clientSecret = "YOUR_STRAVA_CLIENT_SECRET"
    public var redirectURI = "lumen://strava-callback"

    @Published public var isConnected = false
    @Published public var athleteName: String?
    @Published public var status = "Not connected"
    @Published public var activities: [Workout] = []

    private var accessToken: String? { UserDefaults.standard.string(forKey: "strava.token") }
    private var refreshToken: String? { UserDefaults.standard.string(forKey: "strava.refresh") }
    private var expiresAt: Date? { UserDefaults.standard.object(forKey: "strava.expires") as? Date }

    private init() {
        isConnected = accessToken != nil
        if isConnected { status = "Connected — tap Sync" }
    }

    public var authURL: URL? {
        guard clientID != "YOUR_STRAVA_CLIENT_ID" else { return nil }
        var c = URLComponents(string: "https://www.strava.com/oauth/authorize")!
        c.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "approval_prompt", value: "force"),
            .init(name: "scope", value: "read,activity:read_all")
        ]
        return c.url
    }

    public func connect() async {
        guard let url = authURL else { status = "Add Strava Client ID first (see StravaService.swift)"; return }
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "lumen") { callback, _ in
            guard let callback, let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value else { return }
            Task { await self.exchange(code: code) }
        }
        session.presentationContextProvider = AuthContextProvider.shared
        session.prefersEphemeralWebBrowserSession = false
        _ = session.start()
    }

    private func exchange(code: String) async {
        var req = URLRequest(url: URL(string: "https://www.strava.com/oauth/token")!)
        req.httpMethod = "POST"
        let body = "client_id=\(clientID)&client_secret=\(clientSecret)&code=\(code)&grant_type=authorization_code"
        req.httpBody = body.data(using: .utf8)
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
            UserDefaults.standard.set(decoded.access_token, forKey: "strava.token")
            UserDefaults.standard.set(decoded.refresh_token, forKey: "strava.refresh")
            UserDefaults.standard.set(Date().addingTimeInterval(TimeInterval(decoded.expires_in)), forKey: "strava.expires")
            athleteName = "\(decoded.athlete.firstname ?? "") \(decoded.athlete.lastname ?? "")".trimmingCharacters(in: .whitespaces)
            isConnected = true; status = "Connected as \(athleteName ?? "athlete")"
            await sync()
        } catch { status = "Strava auth failed: \(error.localizedDescription)" }
    }

    private func validToken() async -> String? {
        if let exp = expiresAt, exp > Date().addingTimeInterval(60), let t = accessToken { return t }
        guard let refresh = refreshToken else { return accessToken }
        var req = URLRequest(url: URL(string: "https://www.strava.com/oauth/token")!)
        req.httpMethod = "POST"
        let body = "client_id=\(clientID)&client_secret=\(clientSecret)&refresh_token=\(refresh)&grant_type=refresh_token"
        req.httpBody = body.data(using: .utf8)
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
            UserDefaults.standard.set(decoded.access_token, forKey: "strava.token")
            UserDefaults.standard.set(Date().addingTimeInterval(TimeInterval(decoded.expires_in)), forKey: "strava.expires")
            return decoded.access_token
        } catch { return accessToken }
    }

    public func sync(perPage: Int = 30) async {
        guard let token = await validToken() else { status = "Reconnect Strava"; return }
        var req = URLRequest(url: URL(string: "https://www.strava.com/api/v3/athlete/activities?per_page=\(perPage)&page=1")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let list = try decoder.decode([StravaActivity].self, from: data)
            activities = list.map { $0.toWorkout() }
            status = "Synced \(activities.count) activities"
        } catch { status = "Sync failed — check connection" }
    }

    public func disconnect() {
        UserDefaults.standard.removeObject(forKey: "strava.token")
        UserDefaults.standard.removeObject(forKey: "strava.refresh")
        isConnected = false; activities = []; status = "Not connected"
    }

    struct TokenResponse: Decodable {
        var access_token: String; var refresh_token: String; var expires_in: Int
        var athlete: Athlete
        struct Athlete: Decodable { var firstname: String?; var lastname: String? }
    }
    struct StravaActivity: Decodable {
        var id: Int64; var name: String; var type: String; var sport_type: String?
        var start_date: Date; var elapsed_time: Int; var distance: Double?
        var kilojoules: Double?; var average_heartrate: Double?
        var map: StravaMap?
        struct StravaMap: Decodable { var summary_polyline: String? }
        func toWorkout() -> Workout {
            let kind: WorkoutKind
            switch (sport_type ?? type).lowercased() {
            case let s where s.contains("run"): kind = .run
            case let s where s.contains("ride") || s.contains("cycling") || s.contains("bike"): kind = .ride
            case let s where s.contains("swim"): kind = .swim
            case let s where s.contains("walk"): kind = .walk
            case let s where s.contains("hike"): kind = .hike
            case let s where s.contains("weight") || s.contains("strength"): kind = .strength
            case let s where s.contains("hiit") || s.contains("crossfit"): kind = .hiit
            case let s where s.contains("yoga"): kind = .yoga
            case let s where s.contains("row"): kind = .row
            default: kind = .other
            }
            let kcal: Double
            if let kj = kilojoules { kcal = kj * 0.239 }
            else { kcal = kind.met * (Double(elapsed_time) / 3600) * 75 }
            return Workout(kind: kind, title: name, start: start_date, duration: TimeInterval(elapsed_time), activeCalories: kcal, distanceM: distance, avgHR: average_heartrate, source: .strava, stravaID: id, polyline: map?.summary_polyline)
        }
    }
}

final class AuthContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = AuthContextProvider()
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        ASPresentationAnchor()
    }
}

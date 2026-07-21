import Cocoa

// MARK: - Fetch

func fetchUsage(completion: @escaping (UsageResult) -> Void) {
    guard let token = readAccessToken() else {
        completion(UsageResult(error: NO_TOKEN_ERROR))
        return
    }
    guard let url = URL(string: API_URL) else {
        completion(UsageResult(error: "URL 오류")); return
    }
    var req = URLRequest(url: url)
    req.httpMethod = "GET"
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.setValue(OAUTH_BETA, forHTTPHeaderField: "anthropic-beta")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.timeoutInterval = 10

    URLSession.shared.dataTask(with: req) { data, resp, err in
        if let err = err { completion(UsageResult(error: err.localizedDescription)); return }
        guard let http = resp as? HTTPURLResponse else {
            completion(UsageResult(error: "응답 없음")); return
        }
        if http.statusCode == 429 {
            completion(UsageResult(error: "요청이 많아 잠시 대기 중", rateLimited: true)); return
        }
        // 401/403: the token is present but rejected — expired access token.
        if http.statusCode == 401 || http.statusCode == 403 {
            completion(UsageResult(error: EXPIRED_TOKEN_ERROR)); return
        }
        guard http.statusCode == 200, let data = data else {
            completion(UsageResult(error: "HTTP \(http.statusCode)")); return
        }
        completion(parseUsage(data))
    }.resume()
}

func parseUsage(_ data: Data) -> UsageResult {
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let rawLimits = obj["limits"] as? [[String: Any]] else {
        return UsageResult(error: "파싱 실패")
    }
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let isoNoFrac = ISO8601DateFormatter()
    isoNoFrac.formatOptions = [.withInternetDateTime]

    var result = UsageResult()
    for l in rawLimits {
        let kind = l["kind"] as? String ?? "?"
        let percent = (l["percent"] as? NSNumber)?.intValue ?? 0
        let isActive = l["is_active"] as? Bool ?? false
        var resetsAt: Date? = nil
        if let s = l["resets_at"] as? String {
            resetsAt = iso.date(from: s) ?? isoNoFrac.date(from: s)
        }
        var scopeName: String? = nil
        if let scope = l["scope"] as? [String: Any],
           let model = scope["model"] as? [String: Any],
           let name = model["display_name"] as? String {
            scopeName = name
        }
        result.limits.append(Limit(kind: kind, percent: percent,
                                    resetsAt: resetsAt, scopeName: scopeName,
                                    isActive: isActive))
    }
    return result
}

import CryptoKit
import Foundation

struct B2Object: Equatable {
    var name: String
    var key: String
    var isDirectory: Bool
    var size: UInt64
    var modified: Date
}

final class B2Client {
    let config: DriveConfig
    private let session: URLSession

    init(config: DriveConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    func scan(limit: Int = 2000) throws -> DriveUsage {
        var token: String?
        var bytes: UInt64 = 0
        var count = 0
        var folders: [String: (UInt64, Int)] = [:]
        var truncated = false
        repeat {
            var items: [(String, String)] = [
                ("list-type", "2"),
                ("max-keys", "1000"),
            ]
            if let token { items.append(("continuation-token", token)) }
            let data = try request(method: "GET", key: nil, query: items, body: nil)
            let page = try ListBucketParser.parse(data)
            for object in page.objects where !object.isDirectory {
                bytes += object.size
                count += 1
                let folder = object.key.split(separator: "/").first.map(String.init) ?? object.name
                let current = folders[folder] ?? (0, 0)
                folders[folder] = (current.0 + object.size, current.1 + 1)
            }
            token = page.nextToken
            if count >= limit {
                truncated = token != nil
                break
            }
        } while token != nil
        let rows = folders.map { name, value in
            DriveFolder(name: name, bytes: value.0, count: value.1)
        }.sorted { $0.bytes > $1.bytes }
        return DriveUsage(
            bytes: bytes,
            objectCount: count,
            folders: rows,
            truncated: truncated,
            capacity: nativeStorageQuota() ?? Brand.includedBytes
        )
    }

    func probe() throws {
        _ = try request(method: "GET", key: nil, query: [("list-type", "2"), ("max-keys", "1")], body: nil)
    }

    /// B2 Caps & Alerts are a daily dollar spend in the web UI, not a byte quota.
    /// S3 List/Head also has no bucket size cap. Authorize is still worth a look
    /// in case a restricted key ever carries a numeric limit.
    func nativeStorageQuota() -> UInt64? {
        guard config.endpoint.lowercased().contains("backblaze") else { return nil }
        guard let url = URL(string: "https://api.backblazeb2.com/b2api/v2/b2_authorize_account") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        let token = Data("\(config.accessKeyId):\(config.secretAccessKey)".utf8).base64EncodedString()
        request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        let semaphore = DispatchSemaphore(value: 0)
        var payload: [String: Any] = [:]
        session.dataTask(with: request) { data, _, _ in
            if let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                payload = json
            }
            semaphore.signal()
        }.resume()
        semaphore.wait()
        return Self.quotaBytes(in: payload)
    }

    static func quotaBytes(in json: [String: Any]) -> UInt64? {
        func number(_ any: Any?) -> UInt64? {
            if let n = any as? NSNumber {
                let value = n.uint64Value
                return value > 0 ? value : nil
            }
            if let text = any as? String, let value = UInt64(text), value > 0 { return value }
            return nil
        }
        let keys = ["storageCap", "storageLimitBytes", "allowedStorageBytes", "capBytes", "quota", "storageQuota"]
        for key in keys {
            if let value = number(json[key]) { return value }
        }
        if let allowed = json["allowed"] as? [String: Any] {
            for key in keys {
                if let value = number(allowed[key]) { return value }
            }
        }
        return nil
    }

    func list(prefix: String) throws -> [B2Object] {
        var token: String?
        var objects: [B2Object] = []
        repeat {
            var items: [(String, String)] = [
                ("list-type", "2"),
                ("delimiter", "/"),
                ("max-keys", "1000"),
                ("prefix", prefix),
            ]
            if let token { items.append(("continuation-token", token)) }
            let data = try request(method: "GET", key: nil, query: items, body: nil)
            let page = try ListBucketParser.parse(data)
            objects.append(contentsOf: page.objects)
            token = page.nextToken
        } while token != nil
        return objects.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func get(key: String, range: Range<Int>?) throws -> Data {
        var headers: [String: String] = [:]
        if let range {
            headers["range"] = "bytes=\(range.lowerBound)-\(range.upperBound - 1)"
        }
        return try request(method: "GET", key: key, query: [], body: nil, extraHeaders: headers)
    }

    func put(key: String, body: Data, contentType: String = "application/octet-stream") throws {
        _ = try request(
            method: "PUT",
            key: key,
            query: [],
            body: body,
            extraHeaders: ["content-type": contentType]
        )
    }

    func delete(key: String) throws {
        _ = try request(method: "DELETE", key: key, query: [], body: nil)
    }

    func copy(from sourceKey: String, to destinationKey: String) throws {
        let source = "\(config.bucket)/\(sourceKey)".addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? sourceKey
        _ = try request(
            method: "PUT",
            key: destinationKey,
            query: [],
            body: Data(),
            extraHeaders: ["x-amz-copy-source": source]
        )
    }

    func objects(under prefix: String) throws -> [B2Object] {
        var result: [B2Object] = []
        let children = try list(prefix: prefix)
        for child in children {
            result.append(child)
            if child.isDirectory {
                result.append(contentsOf: try objects(under: child.key))
            }
        }
        return result
    }

    func deletePrefix(_ prefix: String) throws {
        for object in try objects(under: prefix) where !object.isDirectory {
            try delete(key: object.key)
        }
        if !prefix.isEmpty {
            try? delete(key: prefix.hasSuffix("/") ? String(prefix.dropLast()) : prefix)
        }
    }

    func relocatePrefix(from: String, to: String) throws {
        let source = from.hasSuffix("/") ? from : from + "/"
        let dest = to.hasSuffix("/") ? to : to + "/"
        for object in try objects(under: source) where !object.isDirectory {
            let next = dest + object.key.dropFirst(source.count)
            try copy(from: object.key, to: String(next))
            try delete(key: object.key)
        }
    }

    private func request(
        method: String,
        key: String?,
        query: [(String, String)],
        body: Data?,
        extraHeaders: [String: String] = [:]
    ) throws -> Data {
        let host = config.endpointURL.host ?? "s3.backblazeb2.com"
        let encodedKey = key.map(Self.encodeKey) ?? ""
        let canonicalURI = "/" + config.bucket + (encodedKey.isEmpty ? "" : "/" + encodedKey)
        var components = URLComponents(url: config.endpointURL, resolvingAgainstBaseURL: false)!
        components.percentEncodedPath = canonicalURI
        if !query.isEmpty {
            components.percentEncodedQuery = Self.canonicalQuery(query)
        }
        guard let url = components.url else { throw URLError(.badURL) }

        let now = Date()
        let amzDate = Self.amzDate(now)
        let payloadHash = SHA256.hash(data: body ?? Data()).hex
        var headers = extraHeaders
        headers["host"] = host
        headers["x-amz-date"] = amzDate
        headers["x-amz-content-sha256"] = payloadHash
        let signedHeaderNames = headers.keys.sorted().joined(separator: ";")
        let canonicalHeaders = headers.keys.sorted()
            .map { "\($0):\((headers[$0] ?? "").trimmingCharacters(in: .whitespaces))\n" }
            .joined()
        let canonical = [
            method,
            canonicalURI,
            Self.canonicalQuery(query),
            canonicalHeaders,
            signedHeaderNames,
            payloadHash,
        ].joined(separator: "\n")
        let scope = "\(Self.dateStamp(now))/\(config.region)/s3/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            scope,
            SHA256.hash(data: Data(canonical.utf8)).hex,
        ].joined(separator: "\n")
        let signature = Self.sign(stringToSign: stringToSign, secret: config.secretAccessKey, date: Self.dateStamp(now), region: config.region)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        for (name, value) in headers where name != "host" {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.setValue(
            "AWS4-HMAC-SHA256 Credential=\(config.accessKeyId)/\(scope), SignedHeaders=\(signedHeaderNames), Signature=\(signature)",
            forHTTPHeaderField: "Authorization"
        )

        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Data, Error> = .failure(URLError(.unknown))
        let task = session.dataTask(with: request) { data, response, error in
            if let error {
                result = .failure(error)
            } else if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                let message = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                result = .failure(B2Error.http(http.statusCode, message))
            } else {
                result = .success(data ?? Data())
            }
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()
        return try result.get()
    }

    static func encodeKey(_ key: String) -> String {
        key.split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
    }

    static func canonicalQuery(_ items: [(String, String)]) -> String {
        let encoded = items.map { pair -> (String, String) in
            (encodeQuery(pair.0), encodeQuery(pair.1))
        }
        let sorted = encoded.sorted { lhs, rhs in
            if lhs.0 == rhs.0 { return lhs.1 < rhs.1 }
            return lhs.0 < rhs.0
        }
        return sorted.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
    }

    private static func encodeQuery(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+")
        return value.addingPercentEncoding(withAllowedCharacters: allowed)?
            .replacingOccurrences(of: "+", with: "%20") ?? value
    }

    private static func amzDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }

    private static func dateStamp(_ date: Date) -> String {
        String(amzDate(date).prefix(8))
    }

    private static func sign(stringToSign: String, secret: String, date: String, region: String) -> String {
        let kDate = HMAC<SHA256>.authenticationCode(for: Data(date.utf8), using: SymmetricKey(data: Data("AWS4\(secret)".utf8)))
        let kRegion = HMAC<SHA256>.authenticationCode(for: Data(region.utf8), using: SymmetricKey(data: Data(kDate)))
        let kService = HMAC<SHA256>.authenticationCode(for: Data("s3".utf8), using: SymmetricKey(data: Data(kRegion)))
        let kSigning = HMAC<SHA256>.authenticationCode(for: Data("aws4_request".utf8), using: SymmetricKey(data: Data(kService)))
        return HMAC<SHA256>.authenticationCode(for: Data(stringToSign.utf8), using: SymmetricKey(data: Data(kSigning))).hex
    }
}

struct DriveFolder: Equatable, Identifiable, Sendable {
    var name: String
    var bytes: UInt64
    var count: Int
    var id: String { name }
}

struct DriveUsage: Equatable, Sendable {
    var bytes: UInt64
    var objectCount: Int
    var folders: [DriveFolder]
    var truncated: Bool
    var capacity: UInt64? = Brand.includedBytes
    var files: Int { objectCount }
    var extraMonthlyDollars: Double {
        guard bytes > Brand.includedBytes else { return 0 }
        let extra = Double(bytes - Brand.includedBytes)
        let blocks = ceil(extra / Double(Brand.extraBlockBytes))
        return blocks * Brand.extraBlockDollars
    }
    var dollars: Double { Brand.individualDollars + extraMonthlyDollars }
}

enum B2Error: Error, CustomStringConvertible {
    case http(Int, String)
    var description: String {
        switch self {
        case .http(let code, let body):
            return "Backblaze HTTP \(code) \(body.prefix(180))"
        }
    }
}

private extension SHA256.Digest {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}

private extension Sequence where Element == UInt8 {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}

private final class ListBucketParser: NSObject, XMLParserDelegate {
    var objects: [B2Object] = []
    var nextToken: String?
    private var text = ""
    private var key = ""
    private var size: UInt64 = 0
    private var modified = Date()
    private var inContents = false
    private var inPrefix = false
    private var truncated = false

    static func parse(_ data: Data) throws -> (objects: [B2Object], nextToken: String?) {
        let parser = ListBucketParser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        guard xml.parse() else { throw xml.parserError ?? B2Error.http(0, "bad list xml") }
        return (parser.objects, parser.truncated ? parser.nextToken : nil)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        text = ""
        if elementName == "Contents" { inContents = true; key = ""; size = 0; modified = Date() }
        if elementName == "CommonPrefixes" { inPrefix = true }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "Key" where inContents: key = value
        case "Size" where inContents: size = UInt64(value) ?? 0
        case "LastModified" where inContents:
            modified = ISO8601DateFormatter().date(from: value) ?? Date()
        case "Contents":
            inContents = false
            if !key.hasSuffix("/") {
                objects.append(B2Object(name: (key as NSString).lastPathComponent, key: key, isDirectory: false, size: size, modified: modified))
            }
        case "Prefix" where inPrefix:
            let prefix = value
            let trimmed = prefix.hasSuffix("/") ? String(prefix.dropLast()) : prefix
            objects.append(B2Object(name: (trimmed as NSString).lastPathComponent, key: prefix, isDirectory: true, size: 0, modified: Date()))
        case "CommonPrefixes": inPrefix = false
        case "IsTruncated": truncated = value == "true"
        case "NextContinuationToken": nextToken = value
        default: break
        }
        text = ""
    }
}

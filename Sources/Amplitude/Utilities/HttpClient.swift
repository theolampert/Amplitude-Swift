//
//  HttpClient.swift
//
//
//  Created by Marvin Liu on 10/28/22.
//

import Foundation

class HttpClient {
    let configuration: Configuration
    internal let session: URLSession
    
    private lazy var dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter
    }()

    init(configuration: Configuration) {
        self.configuration = configuration

        let sessionConfiguration = URLSessionConfiguration.default
        sessionConfiguration.httpMaximumConnectionsPerHost = 2
        sessionConfiguration.urlCache = nil
        self.session = URLSession(configuration: sessionConfiguration, delegate: nil, delegateQueue: nil)
    }

    func upload(events: String, completion: @escaping (_ result: Result<Int, Error>) -> Void) -> URLSessionDataTask? {
        var sessionTask: URLSessionDataTask?
        let backgroundTaskCompletion = VendorSystem.current.beginBackgroundTask()
        do {
            let request = try getRequest()
            let requestData = getRequestData(events: events)

            sessionTask = session.uploadTask(with: request, from: requestData) { data, response, error in
                if error != nil {
                    completion(.failure(error!))
                } else if let httpResponse = response as? HTTPURLResponse {
                    switch httpResponse.statusCode {
                    case 1..<300:
                        completion(.success(httpResponse.statusCode))
                    default:
                        completion(.failure(Exception.httpError(code: httpResponse.statusCode, data: data)))
                    }
                }
                backgroundTaskCompletion?()
            }
            sessionTask!.resume()
        } catch {
            completion(.failure(Exception.httpError(code: 500, data: nil)))
            backgroundTaskCompletion?()
        }
        return sessionTask
    }

    func getUrl() -> String {
        if let url = configuration.serverUrl, !url.isEmpty {
            return url
        }
        if configuration.serverZone == ServerZone.EU {
            return configuration.useBatch ? Constants.EU_BATCH_API_HOST : Constants.EU_DEFAULT_API_HOST
        }
        return configuration.useBatch ? Constants.BATCH_API_HOST : Constants.DEFAULT_API_HOST
    }

    func getRequest() throws -> URLRequest {
        let url = getUrl()
        guard let requestUrl = URL(string: url) else {
            throw Exception.invalidUrl(url: url)
        }
        var request = URLRequest(url: requestUrl, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.addValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    func getRequestData(events: String) -> Data? {
        let apiKey = configuration.apiKey
        let clientUploadTime: String = dateFormatter.string(from: getDate())
        var requestPayload = """
            {"api_key":"\(apiKey)","client_upload_time":"\(clientUploadTime)","events":\(events)
            """
        if let minIdLength = configuration.minIdLength {
            requestPayload += """
                ,"options":{"min_id_length":\(minIdLength)}
                """
        }
        requestPayload += "}"
        return requestPayload.data(using: .utf8)
    }

    func getDate() -> Date {
        return Date()
    }
}

extension HttpClient {
    enum HttpStatus: Int {
        case SUCCESS = 200
        case BAD_REQUEST = 400
        case TIMEOUT = 408
        case PAYLOAD_TOO_LARGE = 413
        case TOO_MANY_REQUESTS = 429
        case FAILED = 500
    }

    enum Exception: Error {
        case invalidUrl(url: String)
        case httpError(code: Int, data: Data?)
    }
}

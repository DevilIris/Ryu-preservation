//
//  M3U8Downloader.swift
//  AnimeLounge
//
//  Created by Francesco on 15/07/24.
//

import Foundation
import Combine

class M3U8Downloader: ObservableObject {
    @Published var downloadProgress: Double = 0.0
    @Published var isDownloading: Bool = false
    @Published var downloadError: String?
    
    private var cancellables = Set<AnyCancellable>()
    private var downloadTask: AnyCancellable?
    
    func downloadAndCombineM3U8(url: URL, outputFileName: String) {
        isDownloading = true
        downloadError = nil

        downloadTask = fetchM3U8(url: url)
            .flatMap { segmentURLs in
                self.combineSegments(segmentURLs: segmentURLs, outputFileName: outputFileName)
            }
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] completion in
                guard let self = self else { return }
                self.isDownloading = false
                if case .failure(let error) = completion {
                    self.downloadError = error.localizedDescription
                }
            }, receiveValue: { _ in })
    }
    
    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        downloadProgress = 0.0
    }
    
    private func fetchM3U8(url: URL) -> Future<[URL], Error> {
        Future { promise in
            URLSession.shared.dataTask(with: url) { data, response, error in
                if let error = error {
                    promise(.failure(error))
                    return
                }

                guard let data = data, let content = String(data: data, encoding: .utf8) else {
                    promise(.failure(NSError(domain: "M3U8Downloader", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid .m3u8 content"])))
                    return
                }

                let segmentURLs = self.parseSegmentURLs(fromContent: content, baseURL: url)
                promise(.success(segmentURLs))
            }.resume()
        }
    }
    
    private func parseSegmentURLs(fromContent content: String, baseURL: URL) -> [URL] {
        content.components(separatedBy: .newlines)
            .filter { $0.hasSuffix(".ts") }
            .compactMap { URL(string: $0, relativeTo: baseURL.deletingLastPathComponent()) }
    }
    
    private func combineSegments(segmentURLs: [URL], outputFileName: String) -> Future<Void, Error> {
        Future { promise in
            DispatchQueue.global(qos: .background).async {
                let outputURL = self.createOutputFileURL(withName: outputFileName)
                
                do {
                    if !FileManager.default.fileExists(atPath: outputURL.path) {
                        FileManager.default.createFile(atPath: outputURL.path, contents: nil, attributes: nil)
                    }
                    
                    let fileHandle = try FileHandle(forWritingTo: outputURL)
                    defer { fileHandle.closeFile() }
                    
                    let totalSegments = segmentURLs.count
                    
                    for (index, segmentURL) in segmentURLs.enumerated() {
                        do {
                            let data = try Data(contentsOf: segmentURL)
                            try fileHandle.seekToEnd()
                            fileHandle.write(data)
                            
                            DispatchQueue.main.async {
                                self.downloadProgress = Double(index + 1) / Double(totalSegments)
                            }
                        } catch {
                            throw NSError(domain: "M3U8Downloader", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to download segment: \(segmentURL)"])
                        }
                    }
                    
                    promise(.success(()))
                } catch {
                    promise(.failure(error))
                }
            }
        }
    }
    
    private func createOutputFileURL(withName fileName: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent(fileName)
    }
}

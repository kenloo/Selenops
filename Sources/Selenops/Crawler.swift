//
//  Crawler.swift
//  
//
//  Created by Federico Zanetello on 2/12/20.
//

import Foundation
import SwiftSoup

/// Receiver of crawler-related events.
public protocol CrawlerDelegate: AnyObject {

  /// Called before the crawler visits a webpage.
  ///
  /// A skipped webpage is not considered among the visited pages.
  func crawler(_ crawler: Crawler, shouldVisitUrl url: URL) -> Bool

  /// Called whenever the crawler is about to visit a new webpage.
  func crawler(_ crawler: Crawler, willVisitUrl url: URL)

  /// Called whenever the crawler finds the searched word in a webpage.
  ///
  /// - Note: This call is fired only (up to) one time per webpage, regardless
  ///   of how many times the word is found in that webpage.
  func crawler(_ crawler: Crawler, didFindWordAt url: URL)

  /// Called once the crawler ends its execution.
  func crawlerDidFinish(_ crawler: Crawler)
}

public extension CrawlerDelegate {
  // Make crawler(crawler:shouldVisitUrl:) optional.
  func crawler(_ crawler: Crawler, shouldVisitUrl url: URL) -> Bool { true }

  // Make crawler(crawler:willVisitUrl:) optional.
  func crawler(_ crawler: Crawler, willVisitUrl url: URL) {}
}

/// A web crawler.
///
/// Given a proper `startURL`, this object will crawl the web looking for the
/// given `wordToSearch` and report its findings.
open class Crawler {

  /// The starting page URL.
  let startURL: URL

  /// The maximum number of pages that the instance will visit.
  ///
  /// - Note: If not enough links are found, the crawler will stop its execution
  ///   prematurely.
  let maximumPagesToVisit: Int

  /// The word the crawler is looking for.
  let wordToSearch: String

  /// The urls of pages the instance has visited already.
  var visitedPages: Set<URL> = []

  /// The urls of pages found during crawling, but yet to visit.
  var pagesToVisit: Set<URL>

  /// The object that acts as the delegate of the crawler.
  public weak var delegate: CrawlerDelegate?

  /// The current `URLSessionDataTask`, if any.
  var currentTask: URLSessionDataTask?

  /// Crawler initializer.
  ///
  /// - Note: After initialization, you must call `start()` in order for the
  ///   instance to start crawling the web.
  ///
  /// - Parameters:
  ///   - startURL: The starting page URL (must contain http:// or https://).
  ///   - maximumPagesToVisit: The maximum number of web pages to visit.
  ///   - word: The word to look for.
  public init(
    startURL: URL,
    maximumPagesToVisit: Int,
    wordToSearch word: String
  ) {
    self.startURL = startURL
    self.pagesToVisit = [startURL]
    self.maximumPagesToVisit = maximumPagesToVisit
    self.wordToSearch = word
  }

  /// Trigger the instance to start crawling the web.
  public func start() {
    crawl()
  }

  /// Immediately ends the crawling process.
  public func cancel() {
    currentTask?.cancel()
    delegate?.crawlerDidFinish(self)
  }

  /// Starts a new crawling cycle.
  func crawl() {
    guard
      visitedPages.count < maximumPagesToVisit,
      let pageToVisit = pagesToVisit.popFirst() else {
      delegate?.crawlerDidFinish(self)
      return
    }

    if visitedPages.contains(pageToVisit) {
      crawl()
    } else {
      if delegate?.crawler(self, shouldVisitUrl: pageToVisit) == true {
        visit(page: pageToVisit)
      } else {
        crawl()
      }
    }
  }

  /// Tells the crawler to visit the given `url` page.
  /// 
  /// - Parameter url: The page we want to visit.
  func visit(page url: URL) {
    visitedPages.insert(url)

    currentTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
      defer { self?.crawl() }
      guard
        let data = data,
        let webpage = String(data: data, encoding: .utf8) else { return }
      self?.parse(webpage, url: url)
    }

    delegate?.crawler(self, willVisitUrl: url)
    currentTask?.resume()
  }

  /// Parses the given document.
  ///
  /// - Parameters:
  ///   - webpage: The content to parse.
  ///   - url: The url associated with the document.
  func parse(_ webpage: String, url: URL) {
    let document: Document? = try? SwiftSoup.parse(webpage, url.absoluteString)

    // Find word in webpage.
    if
      let webpageText: String = try? document?.text(),
      webpageText.range(of: wordToSearch, options: .caseInsensitive) != nil {
      delegate?.crawler(self, didFindWordAt: url)
    }

    // Collect links.
    let anchors: [Element] = (try? document?.select("a").array()) ?? []
    let links: [URL] = anchors.compactMap({ try? $0.absUrl("href") }).compactMap(URL.init(string:))
    pagesToVisit.formUnion(links)
  }
}

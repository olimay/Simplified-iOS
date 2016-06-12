import Foundation

/// This class conforms to draft-nottingham-http-problem-03. See 
/// https://tools.ietf.org/html/draft-nottingham-http-problem-03 for further information.
@objc class ProblemDetail: NSObject {
  let problemType: NSURL
  let title: String
  let httpStatus: Int?
  let detail: String?
  let problemInstance: NSURL?
  
  /// `JSON` must be a dictionary. It must have a key `"problemType"` with an associated
  /// `String` that can be parsed as an `NSURL` and it must have a key `"title"` with an
  /// associated `String`. For example:
  ///
  /// `{ "problemType" = "http://exmaple.com/example-error", "title" = "Example Error" }`
  ///
  /// Optional fields as indicated in the specification may also be present. This includes
  /// `"httpStatus"` (which must map to a value castable to `Int`), `"detail"` (which must
  /// map to a `String`), and `"problemInstance"` (which must map to a `String` that can
  /// be parsed as an `NSURL`). Optional fields with incorrect types will be ignored.
  init?(JSON: [String: AnyObject]) {
    guard
      let problemTypeString = JSON["problemType"] as? String,
      let problemType = NSURL(string: problemTypeString),
      let title = JSON["title"] as? String else
    {
      return nil
    }
    
    self.problemType = problemType
    self.title = title
    
    self.httpStatus = JSON["httpStatus"] as? Int
    self.detail = JSON["detail"] as? String
    if let problemInstanceString = JSON["problemInstance"] as? String {
      self.problemInstance = NSURL(string: problemInstanceString)
    } else {
      self.problemInstance = nil
    }
  }
}

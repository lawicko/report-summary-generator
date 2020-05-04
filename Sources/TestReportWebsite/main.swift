import Files
import Foundation
import Publish
import Plot
import Sweep

struct TestReportWebsite: Website {
    enum SectionID: String, WebsiteSectionID {
        // Add the sections that you want your website to contain here:
        case reports
    }

    struct ItemMetadata: WebsiteItemMetadata {
        var descriptionIndicatorColor: String
    }

    // Update these properties to configure your website:
    var url = URL(string: "https://s3.eu-central-1.amazonaws.com/ios.test-reports.tutti.systems")!
    var name = "tutti.ch iOS test reports"
    var description = "This site contains the test reports generated by bitrise."
    var language: Language { .english }
    var imagePath: Path? { nil }
    var favicon = Favicon()
    static let defaultReportPath: Path = "Resources/original_reports"
}

// MARK: publishing specific
extension TestReportWebsite {
    @discardableResult
    func publish(at path: Path? = nil) throws -> PublishedWebsite<TestReportWebsite> {
        return try publish(at: path, using: [
            .optional(.copyResources()),
            .addItemsFromReports(),
            .sortItems(by: \.date, order: .descending),
            .generateHTML(withTheme: .tutti, indentation: nil),
            .unwrap(.default) { config in
                .generateRSSFeed(
                    including: Set(SectionID.allCases),
                    config: config
                )
            },
            .generateSiteMap(indentedBy: nil)
        ])
    }
}

try TestReportWebsite().publish()

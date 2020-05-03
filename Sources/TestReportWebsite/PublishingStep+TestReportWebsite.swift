//
//  PublishingStep+TestReportWebsite.swift
//  
//
//  Created by Jakub Lawicki on 3 May 20.
//

import Files
import Foundation
import Publish
import Plot
import Sweep

// MARK: supported report types
fileprivate enum ReportTypes: String, RawRepresentable {
    case unittest
    case slather
    case swiftlint
    case xcov
}

fileprivate enum FileTypes: String, RawRepresentable {
    case html
    case json
    case junit
    case xml
}

fileprivate let defaultFileTypesPreference = Array<FileTypes>(arrayLiteral:.html, .xml, .junit)
fileprivate let numberFormatter: NumberFormatter = {
    let nf = NumberFormatter()
    nf.numberStyle = .percent
    return nf
}()

extension PublishingStep {
    static func addItemsFromReports(at path: Path = TestReportWebsite.defaultReportPath) -> PublishingStep<TestReportWebsite> {
        PublishingStep<TestReportWebsite>.step(named: "Adding items from '\(path)' folder") { context in
            let folder = try context.folder(at: path)
            for folder in folder.subfolders {
                try addItem(from:folder, context: &context)
            }
        }
    }

    static func addItem(from folder: Folder, context: inout PublishingContext<TestReportWebsite>) throws {
        switch folder.name {
        case let str where str.contains(ReportTypes.xcov.rawValue):
            try addItem(.xcov, from: folder, context: &context)
        case let str where str.contains(ReportTypes.swiftlint.rawValue):
            try addItem(.swiftlint, from: folder, context: &context)
        case let str where str.contains(ReportTypes.unittest.rawValue):
            try addItem(.unittest, from: folder, context: &context)
        case let str where str.contains(ReportTypes.slather.rawValue):
            try addItem(.slather, from: folder, context: &context)
        default:
            print("WARNING: Unknown report type in \(folder.name)")
        }
    }

    fileprivate static func addItem(_ type: ReportTypes, from folder: Folder, context: inout PublishingContext<TestReportWebsite>) throws {
        guard !folder.files.names().isEmpty else {
            print("The folder \(folder.name) doesn't contain any files at the root level, skipping..")
            return
        }

        guard let file = findFile(in: folder) else {
            print("Could not find a file with any of the supported extensions in folder \(folder.name), skipping...")
            return
        }

        try addItem(type, from: file, folder: folder, context: &context)
    }

    fileprivate static func addItem(_ type: ReportTypes,
                                    from file: File,
                                    folder: Folder,
                                    context: inout PublishingContext<TestReportWebsite>) throws {
        let creationDate = file.creationDate
        let modificationDate = file.modificationDate
        let contents = try file.readAsString()
        var title = titleFrom(htmlString: contents) ?? "\(type.rawValue) report"
        let linkAddress = "/original_reports/\(folder.name)/\(file.name)"

        let fileType = FileTypes.init(rawValue: file.extension!)!
        let specificData = getSpecificData(for: type, fileType: fileType, contents: contents, footerLinkAddress: linkAddress)

        if let cDate = creationDate {
            title = "\(title) from \(context.dateFormatter.string(from: cDate))"
        }
        let content = Content(title: title,
                              description: specificData.description,
                              body: Content.Body(html: specificData.html.render()),
                              date: creationDate ?? Date(),
                              lastModified: modificationDate ?? Date())
        context.addItem(Item(path: Path(folder.name),
                             sectionID: .reports,
                             metadata: specificData.metadata,
                             tags: specificData.tags,
                             content: content))
    }

    fileprivate static func getSpecificData(for reportType: ReportTypes, fileType: FileTypes, contents: String, footerLinkAddress: String) -> SpecificDataType {
        switch reportType {
        case .swiftlint:
            return getSwiftlintSpecificData(contents: contents, fileType: fileType, footerLinkAddress: footerLinkAddress)
        case .slather:
            return getSlatherSpecificData(contents: contents, fileType: fileType, footerLinkAddress: footerLinkAddress)
        case .unittest:
            return getUnittestSpecificData(contents: contents, fileType: fileType, footerLinkAddress: footerLinkAddress)
        case .xcov:
            return getXcovSpecificData(contents: contents, fileType: fileType, footerLinkAddress: footerLinkAddress)
        }
    }

    // MARK: -
    // MARK: Slather

    fileprivate static func getSlatherSpecificData(contents: String, fileType: FileTypes, footerLinkAddress: String) -> SpecificDataType {
        var percentage: String
        var formattedPercentage: String
        switch fileType {
        case .xml:
            percentage = String(contents.firstSubstring(between: "line-rate=\"", and: "\"")!)
            formattedPercentage = formatedPercentage(String(percentage))
        case .html:
            formattedPercentage = String(contents.firstSubstring(between: "id=\"total_coverage\">", and: "</span>")!)
            percentage = formattedPercentage.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        default:
            fatalError("This file type is not supported")
        }

        let statusColor = getColor(from: String(percentage))

        let html = slatherHTML(statusColor: statusColor, percentage: formattedPercentage, footerLinkAddress: footerLinkAddress)
        let metadata = getMetadata(from: String(statusColor))
        let tags = slatherTags()

        return SpecificDataType(html: html, description: formattedPercentage, metadata: metadata, tags: tags)
    }

    fileprivate static func slatherHTML(statusColor: String,
                                        percentage: String,
                                        footerLinkAddress: String) -> HTML {
        return HTML(
            .body(
                .div(
                    .h3(
                        .span(.style("color: \(statusColor)"), "⬤"),
                        .span(" \(percentage)")
                    ),
                    .br(),
                    .p(
                        .a(.class("link"), .href(footerLinkAddress), "The original report available here")
                    )
                )
            )
        )
    }

    fileprivate static func slatherTags() -> Array<Tag> {
        return ["slather", "coverage", "report"]
    }

    // MARK: -
    // MARK: Xcov

    fileprivate static func getXcovSpecificData(contents: String, fileType: FileTypes, footerLinkAddress: String) -> SpecificDataType {
        let percentage = contents.firstSubstring(between: "<div class=\"summary-counter\">", and: "</div>")!
        let colorPrefix = "<div class=\"summary-description\" style=\"color: "
        let colorSuffix = ";\">"
        let summaryDescriptionColor = contents.firstSubstring(between: Identifier(stringLiteral:colorPrefix),
                                                           and: Terminator(stringLiteral:colorSuffix))!
        let colorTag = colorPrefix + summaryDescriptionColor + colorSuffix
        let summaryDescriptionSubstring = contents.firstSubstring(between: Identifier(stringLiteral:colorTag), and: "</div>")!

        let html = xcovHTML(statusColor: String(summaryDescriptionColor),
                            percentage: String(percentage),
                            descriptionString: String(summaryDescriptionSubstring),
                            footerLinkAddress: footerLinkAddress)

        let metadata = getMetadata(from: String(summaryDescriptionColor))
        let tags = xcovTags()

        let formattedSummary = "\(percentage) \(summaryDescriptionSubstring)"

        return SpecificDataType(html: html, description: formattedSummary, metadata: metadata, tags: tags)
    }

    fileprivate static func xcovHTML(statusColor: String,
                                     percentage: String,
                                     descriptionString: String,
                                     footerLinkAddress: String) -> HTML {
        return HTML(
            .body(
                .div(
                    .h3(
                        .span(.style("color: \(statusColor)"), "⬤"),
                        .span("\(percentage) \(descriptionString)")
                    ),
                    .br(),
                    .p(
                        .a(.class("link"), .href(footerLinkAddress), "The original report available here")
                    )
                )
            )
        )
    }

    fileprivate static func xcovTags() -> Array<Tag> {
        return ["xcov", "coverage", "report"]
    }

    // MARK: -
    // MARK: Unit test

    fileprivate static func getUnittestSpecificData(contents: String, fileType: FileTypes, footerLinkAddress: String) -> SpecificDataType {
        var allScenarios: String
        var passed: Substring
        var failed: Substring
        switch fileType {
        case .junit:
            passed = contents.firstSubstring(between: "tests='", and: "'")!
            failed = contents.firstSubstring(between: "failures='", and: "'")!
            allScenarios = String(Int(passed)! + Int(failed)!)
        case .html:
            allScenarios = String(contents.firstSubstring(between: "All (", and: ")")!)
            passed = contents.firstSubstring(between: "Passed (", and: ")")!
            failed = contents.firstSubstring(between: "Failed (", and: ")")!
        default:
            fatalError("This file type is not supported")
        }

        var descriptionString = " \(allScenarios) tests: \(passed) passed"

        var dotColor = "#24A300"
        let failedNo = Int(failed)!
        if failedNo>0 {
            dotColor = "#ED2C28"
            descriptionString.append(", \(failed) failed")
        }

        let html = unittestHTML(statusColor: dotColor, descriptionString: descriptionString, footerLinkAddress: footerLinkAddress)
        let metadata = getMetadata(from: dotColor)
        let tags = unittestTags()

        return SpecificDataType(html: html, description: descriptionString, metadata: metadata, tags: tags)
    }

    fileprivate static func unittestHTML(statusColor: String,
                                         descriptionString: String,
                                         footerLinkAddress: String) -> HTML {
        return HTML(
            .body(
                .div(
                    .h3(
                        .span(.style("color: \(statusColor)"), "⬤"),
                        .span("\(descriptionString)")
                    ),
                    .br(),
                    .p(
                        .a(.class("link"), .href(footerLinkAddress), "The original report available here")
                    )
                )
            )
        )
    }

    fileprivate static func unittestTags()  -> Array<Tag> {
        return ["unit test", "test", "report"]
    }

    // MARK: -
    // MARK: Swiftlint

    fileprivate static func getSwiftlintSpecificData(contents: String, fileType: FileTypes, footerLinkAddress: String) -> SpecificDataType {
        var violations: String
        var warnings: String
        var errors: String
        switch fileType {
        case .html:
            warnings = contents.firstSubstring(between: "Total warnings", and: "Total errors")!.trimmingCharacters(in: CharacterSet.decimalDigits.inverted)
            errors = contents.firstSubstring(between: "Total errors", and: "</tr>")!.trimmingCharacters(in: CharacterSet.decimalDigits.inverted)
            let errorNo = Int(errors)!
            let warningNo = Int(warnings)!
            violations = String(errorNo + warningNo)
        case .junit:
            let errorNo = contents.components(separatedBy: "error:").count - 1
            let warnNo = contents.components(separatedBy: "warning:").count - 1
            errors = String(errorNo)
            warnings = String(warnNo)
            violations = String(errorNo + warnNo)
        default:
            fatalError("Format not supported: \(fileType.rawValue)")
        }


        var dotColor = "#24A300"
        let errorNo = Int(errors)!
        let warnNo = Int(warnings)!
        if errorNo>0 {
            dotColor = "#ED2C28"
        } else if warnNo>0 {
            dotColor = "#FFCB05"
        }

        let html = swiftlintHTML(statusColor: dotColor,
                                 violations: violations,
                                 errors: errors,
                                 warnings: warnings,
                                 footerLinkAddress: footerLinkAddress)
        let description = swiftlintDescription(violations: violations, errors: errors, warnings: warnings)
        let metadata = getMetadata(from: dotColor)
        let tags = swiftlintTags()
        return SpecificDataType(html: html, description: description, metadata: metadata, tags: tags)
    }

    fileprivate static func swiftlintHTML(statusColor: String,
                              violations: String,
                              errors: String,
                              warnings: String,
                              footerLinkAddress: String) -> HTML {
        return HTML(
            .body(
                .div(
                    .h3(
                        .span(.style("color: \(statusColor)"), "⬤"),
                        .span(" \(violations) violations: \(errors) errors and \(warnings) warnings")
                    ),
                    .br(),
                    .p(
                        .a(.class("link"), .href(footerLinkAddress), "The original report available here")
                    )
                )
            )
        )
    }

    fileprivate static func swiftlintDescription(violations: String,
                                     errors: String,
                                     warnings: String) -> String {
        return "\(violations) violations: \(errors) errors and \(warnings) warnings"
    }

    fileprivate static func swiftlintTags() -> Array<Tag> {
        return ["swiftlint", "lint", "report"]
    }

    // MARK: -
    // MARK: Helpers

    fileprivate static func formatedPercentage(_ percentage: String) -> String {
        let asDouble = Double(percentage)
        let asNSNumber = NSNumber(value: asDouble!)
        return numberFormatter.string(from: asNSNumber)!
    }

    fileprivate static func getColor(from percentage: String) -> String {
        guard let num = Double(percentage) else {
            return "#000000"
        }
        switch num {
        case 0..<25:
            return "#ED2C28"
        case 25..<50:
            return "#F27A29"
        case 50..<75:
            return "#FFCB05"
        default:
            return "#24A300"
        }
    }

    fileprivate static func getMetadata(from statusColor: String) -> TestReportWebsite.ItemMetadata {
        return TestReportWebsite.ItemMetadata(descriptionIndicatorColor: statusColor)
    }

    fileprivate static func titleFrom(htmlString str: String) -> String? {
        guard let titleSubstring = str.substrings(between: "<title>", and: "</title>").first else {
            return nil
        }
        return String(titleSubstring)
    }

    fileprivate static func findFile(in folder: Folder, preference: Array<FileTypes>=defaultFileTypesPreference) -> File? {
        var file: File?
        var preferenceArray = preference
        repeat {
            // Special handling for html is needed, because for some tools there is a lot of html files and we are only interested in index.html or possibly in the onest that have 'report' in the name
            if preferenceArray.first!.rawValue == "html" {
                file = folder.files.first { $0.name == "index.html" }
                if file != nil { break }
                file = folder.files.first { $0.name.contains("report") }
                if file != nil { break }
            }

            let ext = preferenceArray.removeFirst().rawValue
            file = folder.files.first(where: { (file) -> Bool in
                guard let e = file.extension else { return false }
                guard e == ext else { return false }
                return true
            })
        } while !preferenceArray.isEmpty && file == nil

        return file
    }
}

//
//  import-check
//
//  Runs the spreadsheet import logic (Stash/Import/, Foundation-only files)
//  against every file in docs/import-test-files/ and prints the plan each one
//  produces, with a pass/fail line for each expectation in the spec's
//  expected-results table. There is no test target, so this is the test.
//
//  Run it with scripts/import-check/run.sh from the repository root.
//  It lives outside Stash/ on purpose: everything under Stash/ is compiled
//  into the app.
//

import Foundation

// Everything runs from a nonisolated function. The app builds with MainActor
// as the default isolation, and so does run.sh, so this file only compiles if
// the import code really is callable off the main actor.

nonisolated struct Checker {
    var passed = 0
    var failed: [String] = []
    var section = ""

    mutating func expect(_ what: String, _ condition: Bool) {
        if condition {
            passed += 1
            print("  PASS  \(what)")
        } else {
            failed.append("\(section): \(what)")
            print("  FAIL  \(what)")
        }
    }
}

nonisolated struct Scenario {
    var title: String
    var file: String
    var asPaste = false
    var options = ImportOptions()
    var existing = ImportTreeSnapshot()
    /// Changes to the automatic mapping, as the user would make on the
    /// "Match your columns" screen.
    var remap: [(heading: String, role: ImportRole)] = []
}

nonisolated struct Outcome {
    var sheet: ParsedSpreadsheet
    var mapping: ImportMapping
    var plan: ImportPlan

    func item(_ name: String) -> ImportPlan.PlannedItem? {
        plan.items.first { $0.name == name }
    }

    func role(of heading: String) -> ImportRole? {
        guard mapping.hasHeaderRow, let index = sheet.rows.first?.firstIndex(of: heading) else { return nil }
        return mapping.roles[index]
    }

    var newPaths: [String] { plan.newLocations.map { $0.path.joined(separator: " › ") } }
}

nonisolated func describe(_ item: ImportPlan.PlannedItem) -> String {
    var line = (item.path + [item.name]).joined(separator: " › ")
    if let quantity = item.quantity {
        line += "  ×\(quantity)"
        if let unit = item.unit { line += " \(unit)" }
    }
    if let minimum = item.minimum { line += "  (min \(minimum))" }
    if let expiry = item.expiry { line += "  expires \(expiry.dayMonthYear)" }
    return line
}

nonisolated func run(_ scenario: Scenario, directory: URL) -> Outcome? {
    print("")
    print(String(repeating: "=", count: 78))
    print(scenario.title)
    print(String(repeating: "=", count: 78))

    let url = directory.appendingPathComponent(scenario.file)
    guard let data = try? Data(contentsOf: url) else {
        print("  Could not read \(url.path)")
        return nil
    }

    let sheet: ParsedSpreadsheet
    do {
        if scenario.asPaste {
            // The paste route hands the parser a String, not bytes.
            sheet = try SpreadsheetParser.parse(text: String(decoding: data, as: UTF8.self))
        } else {
            sheet = try SpreadsheetParser.parse(data: data)
        }
    } catch let error as SpreadsheetParseError {
        print("  Parse failed: \(error.message)")
        return nil
    } catch {
        print("  Parse failed: \(error)")
        return nil
    }

    var mapping = ImportAutoMapper.autoMap(rows: sheet.rows)
    for change in scenario.remap {
        if let index = sheet.rows.first?.firstIndex(of: change.heading) {
            mapping.setRole(change.role, forColumn: index)
        }
    }
    let plan = ImportPlanner.plan(rows: sheet.rows, mapping: mapping, options: scenario.options, existing: scenario.existing)

    print("Read as:    \(sheet.encoding), delimiter \(sheet.delimiter.rawValue), "
          + "\(sheet.rows.count) rows × \(sheet.columnCount) columns")
    print("Headings:   first row is \(mapping.hasHeaderRow ? "headings" : "data")")
    print("Columns:")
    for column in ImportAutoMapper.columns(for: sheet.rows, hasHeaderRow: mapping.hasHeaderRow) {
        let changed = scenario.remap.contains { $0.heading == column.label } ? "  (changed by hand)" : ""
        let label = column.label.padding(toLength: 14, withPad: " ", startingAt: 0)
        print("  \(label) → \(mapping.roles[column.index].title)\(changed)")
    }
    if let dateOrder = plan.dateOrder {
        let why: String
        switch dateOrder.source {
        case .detected: why = "worked out from the column"
        case .regionDefault: why = "nothing in the column settles it, so region default"
        case .chosen: why = "chosen by hand"
        }
        print("Dates:      \(dateOrder.order.summary) (\(why))")
    }
    if plan.fillDownApplies {
        print("Fill down:  \(scenario.options.fillDown ? "on" : "off") (the toggle would be shown)")
    }

    print("")
    print("PLAN:       \(plan.summary)")
    if plan.hasAnythingToImport {
        print("            (spaces on the items' paths: \(plan.spaceCount); spaces items go straight into: \(plan.targetSpaceCount))")
        print("Result:     \(plan.resultMessage)")
    } else if plan.duplicateCount > 0 {
        print("            \(plan.duplicateCount) duplicates skipped, \(plan.newSpaceCount) new spaces")
    }
    if !plan.newLocations.isEmpty {
        print("New spaces:")
        for location in plan.newLocations { print("  + \(location.path.joined(separator: " › "))") }
    }
    if !plan.warnings.isEmpty {
        print("Warnings:")
        for warning in plan.warnings { print("  ! \(warning)") }
    }
    if !plan.items.isEmpty {
        print("Items:")
        for item in plan.items {
            print("  \(describe(item))")
            if let notes = item.notes {
                for line in notes.components(separatedBy: "\n") { print("        notes │ \(line)") }
            }
        }
    }
    if !plan.skipped.isEmpty {
        print("Skipped:")
        for skip in plan.skipped {
            let reason: String
            switch skip.reason {
            case .noName: reason = "no item name"
            case .alreadyExists: reason = "already exists"
            case .repeatedInFile: reason = "exact copy of an earlier row"
            case .freeLimit: reason = "free plan limit"
            }
            print("  row \(skip.row): \(skip.name.isEmpty ? "(blank)" : skip.name) (\(reason))")
        }
    }
    print("")
    return Outcome(sheet: sheet, mapping: mapping, plan: plan)
}

/// What the store looks like after a plan is written. Stands in for
/// ImportWriter so the re-import case has something to import into.
nonisolated func snapshot(afterApplying plan: ImportPlan, to existing: ImportTreeSnapshot) -> ImportTreeSnapshot {
    var result = existing
    var newIDs: [UUID] = []
    func id(for ref: ImportPlan.LocationRef) -> UUID {
        switch ref {
        case .existing(let id): return id
        case .new(let index): return newIDs[index]
        }
    }
    for location in plan.newLocations {
        let newID = UUID()
        result.nodes.append(ImportTreeSnapshot.Node(
            id: newID, name: location.name, parentID: location.parent.map(id(for:)), dateCreated: Date()
        ))
        newIDs.append(newID)
    }
    for item in plan.items {
        let target = id(for: item.target)
        if let index = result.nodes.firstIndex(where: { $0.id == target }) {
            result.nodes[index].itemNames.append(item.name)
        }
    }
    return result
}

nonisolated func runAll(directory: URL) -> Bool {
    var check = Checker()
    let day = { (year: Int, month: Int, day: Int) in ImportDay(year: year, month: month, day: day) }

    // MARK: 01 simple path

    check.section = "01"
    var afterFirstImport = ImportTreeSnapshot()
    if let out = run(Scenario(title: "01-simple-path.csv   (top level, empty store)", file: "01-simple-path.csv"), directory: directory) {
        check.expect("6 items", out.plan.items.count == 6)
        check.expect("Areas are Kitchen, Garage, Bathroom",
                     Set(out.plan.newLocations.filter { $0.parent == nil }.map(\.name)) == ["Kitchen", "Garage", "Bathroom"])
        check.expect("Paracetamol expires 31/03/2027", out.item("Paracetamol")?.expiry == day(2027, 3, 31))
        check.expect("Plasters expires 30/11/2026 (from 11/2026)", out.item("Plasters")?.expiry == day(2026, 11, 30))
        check.expect("Units read (Paracetamol ×2 boxes)", out.item("Paracetamol")?.quantity == 2 && out.item("Paracetamol")?.unit == "boxes")
        check.expect("Dates read as day/month/year", out.plan.dateOrder?.order == .dayFirst && out.plan.dateOrder?.source == .detected)
        afterFirstImport = snapshot(afterApplying: out.plan, to: ImportTreeSnapshot())
    }

    // MARK: 02 level columns

    check.section = "02"
    if let out = run(Scenario(title: "02-level-columns.csv   (top level, empty store)", file: "02-level-columns.csv"), directory: directory) {
        check.expect("8 items", out.plan.items.count == 8)
        check.expect("Room, Cupboard, Shelf map to levels 1, 2, 3",
                     out.role(of: "Room") == .locationLevel(1) && out.role(of: "Cupboard") == .locationLevel(2) && out.role(of: "Shelf") == .locationLevel(3))
        let kitchenRows = ["Spare light bulbs", "Fuses", "Picnic blanket", "Flask", "Bin bags", "Dishwasher tablets"]
        check.expect("Fill down puts all six Kitchen rows under Kitchen",
                     kitchenRows.allSatisfy { out.item($0)?.path.first == "Kitchen" })
        check.expect("Fuses fills down to Kitchen › Tall cupboard › Top", out.item("Fuses")?.path == ["Kitchen", "Tall cupboard", "Top"])
        check.expect("Flask fills down to Kitchen › Tall cupboard › Middle", out.item("Flask")?.path == ["Kitchen", "Tall cupboard", "Middle"])
        check.expect("A new Cupboard resets Shelf (Bin bags in Kitchen › Under sink)", out.item("Bin bags")?.path == ["Kitchen", "Under sink"])
        check.expect("Dishwasher tablets stays in Kitchen › Under sink", out.item("Dishwasher tablets")?.path == ["Kitchen", "Under sink"])
        check.expect("Torch fills down to Hallway › Coat cupboard", out.item("Torch")?.path == ["Hallway", "Coat cupboard"])
    }

    // MARK: 03 semicolon Excel

    check.section = "03"
    if let out = run(Scenario(title: "03-semicolon-excel.csv   (top level, empty store)", file: "03-semicolon-excel.csv"), directory: directory) {
        check.expect("Delimiter detected as semicolon", out.sheet.delimiter == .semicolon)
        check.expect("Heading \"Item\" maps to Item name (no BOM junk)",
                     out.sheet.rows.first?.first == "Item" && out.role(of: "Item") == .itemName)
        check.expect("Qty and Best before headings map", out.role(of: "Qty") == .quantity && out.role(of: "Best before") == .expiry)
        check.expect("4 items, all with quantities", out.plan.items.count == 4 && out.plan.items.allSatisfy { $0.quantity != nil })
        check.expect("Quantities are 2, 5, 8, 1", out.plan.items.map(\.quantity) == [2, 5, 8, 1])
        check.expect("No stray carriage returns in the last column", out.sheet.rows.allSatisfy { !($0.last ?? "").contains("\r") })
    }

    // MARK: 04 pasted from Numbers

    check.section = "04"
    let fromFile = run(Scenario(title: "04-pasted-from-numbers.txt   (read as a file)", file: "04-pasted-from-numbers.txt"), directory: directory)
    let fromPaste = run(Scenario(title: "04-pasted-from-numbers.txt   (through Paste Rows)", file: "04-pasted-from-numbers.txt", asPaste: true), directory: directory)
    if let fromFile, let fromPaste {
        check.expect("Delimiter detected as tab", fromFile.sheet.delimiter == .tab && fromPaste.sheet.delimiter == .tab)
        check.expect("5 items", fromFile.plan.items.count == 5)
        check.expect("Paste Rows gives the identical plan",
                     fromFile.plan.items == fromPaste.plan.items && fromFile.plan.newLocations == fromPaste.plan.newLocations)
    }

    // MARK: 05 messy

    check.section = "05"
    if let out = run(Scenario(title: "05-messy.csv   (top level, empty store, automatic mapping)", file: "05-messy.csv"), directory: directory) {
        check.expect("7 items imported", out.plan.items.count == 7)
        check.expect("2 rows skipped for having no name", out.plan.skipCount(.noName) == 2 && out.plan.skipped.count == 2)
        check.expect("Quoted comma survives (\"Screws, assorted\")", out.item("Screws, assorted") != nil)
        check.expect("\"3 tubes\" gives 3, unit tubes", out.item("Screws, assorted")?.quantity == 3 && out.item("Screws, assorted")?.unit == "tubes")
        check.expect("\"x2\" gives 2", out.item("Wood glue")?.quantity == 2)
        check.expect("\"about a dozen\" gives no quantity, text kept in notes",
                     out.item("Sandpaper")?.quantity == nil && out.item("Sandpaper")?.notes == "Quantity: about a dozen")
        check.expect("Bad date gives no expiry, notes \"Expiry: soonish\"",
                     out.item("Wood glue")?.expiry == nil && out.item("Wood glue")?.notes == "Expiry: soonish")
        check.expect("Brand auto-maps to Ignore", out.role(of: "Brand") == .ignore)
        check.expect("Link appended to notes on its own line",
                     out.item("Drill bits")?.notes?.components(separatedBy: "\n").last == "https://www.bosch-diy.com")
        check.expect("Head torch fills down into Garage › Shelf 3", out.item("Head torch")?.path == ["Garage", "Shelf 3"])
        check.expect("Quoted newline survives as a two-line note",
                     out.item("Drill bits")?.notes?.hasPrefix("Masonry and wood,\nboth sets") == true)
        check.expect("Doubled quotes survive", out.item("Dust sheets")?.notes == "She said \"the big ones\"")
    }
    if let out = run(Scenario(title: "05-messy.csv   (same, with Brand changed to Add to notes)", file: "05-messy.csv",
                              remap: [("Brand", .addToNotes)]), directory: directory) {
        check.expect("Brand as Add to notes gives \"Brand: …\"",
                     out.item("Head torch")?.notes == "Brand: Petzl" && out.item("Screws, assorted")?.notes == "Brand: Spax")
        check.expect("Notes order is comment, Brand, link",
                     out.item("Drill bits")?.notes == "Masonry and wood,\nboth sets\nBrand: Bosch\nhttps://www.bosch-diy.com")
    }

    // MARK: 06 names only

    check.section = "06"
    if let out = run(Scenario(title: "06-names-only.csv   (top level, empty store)", file: "06-names-only.csv"), directory: directory) {
        check.expect("Header toggle off", out.mapping.hasHeaderRow == false)
        check.expect("The one column is the item name", out.mapping.roles == [.itemName])
        check.expect("5 items", out.plan.items.count == 5)
        check.expect("All into Unsorted", out.plan.items.allSatisfy { $0.path == ["Unsorted"] }
                     && out.plan.newLocations.count == 1 && out.plan.newLocations.first?.isUnsortedArea == true)
    }
    do {
        let hallID = UUID(), drawerID = UUID()
        var scenario = Scenario(title: "06-names-only.csv   (into the chosen destination Hall › Drawer)", file: "06-names-only.csv")
        scenario.options.destination = .location(drawerID)
        scenario.existing = ImportTreeSnapshot(nodes: [
            .init(id: hallID, name: "Hall", parentID: nil, dateCreated: Date(timeIntervalSince1970: 1)),
            .init(id: drawerID, name: "Drawer", parentID: hallID, dateCreated: Date(timeIntervalSince1970: 2)),
        ])
        if let out = run(scenario, directory: directory) {
            check.expect("5 items straight into the chosen destination, nothing created",
                         out.plan.items.count == 5 && out.plan.items.allSatisfy { $0.target == .existing(drawerID) } && out.plan.newLocations.isEmpty)
        }
    }

    // MARK: 07 US dates

    check.section = "07"
    if let out = run(Scenario(title: "07-us-dates.csv   (top level, empty store, UK region)", file: "07-us-dates.csv"), directory: directory) {
        check.expect("Column read as month/day/year", out.plan.dateOrder?.order == .monthFirst && out.plan.dateOrder?.source == .detected)
        check.expect("Preview says so", out.plan.dateOrder?.order.summary == "Dates read as month/day/year")
        check.expect("06/15/2027 is 15 June", out.item("Sun cream")?.expiry == day(2027, 6, 15))
        check.expect("12/31/2027 is 31 December", out.item("Insect repellent")?.expiry == day(2027, 12, 31))
        check.expect("03/01/2027 is 1 March, not 3 January", out.item("Hay fever tablets")?.expiry == day(2027, 3, 1))
    }

    // MARK: 08 oil paints

    check.section = "08"
    do {
        let studioID = UUID(), cabinetID = UUID()
        var scenario = Scenario(title: "08-oil-paints.csv   (into Studio › Paint cabinet; Brand and Size changed to Add to notes)",
                                file: "08-oil-paints.csv", remap: [("Brand", .addToNotes), ("Size", .addToNotes)])
        scenario.options.destination = .location(cabinetID)
        scenario.existing = ImportTreeSnapshot(nodes: [
            .init(id: studioID, name: "Studio", parentID: nil, dateCreated: Date(timeIntervalSince1970: 1)),
            .init(id: cabinetID, name: "Paint cabinet", parentID: studioID, dateCreated: Date(timeIntervalSince1970: 2)),
        ])
        if let out = run(scenario, directory: directory) {
            check.expect("Drawer auto-maps to level 1", out.role(of: "Drawer") == .locationLevel(1))
            check.expect("Colour auto-maps to item name", out.role(of: "Colour") == .itemName)
            check.expect("6 items", out.plan.items.count == 6)
            check.expect("Drawer 1 and Drawer 2 created beneath Studio › Paint cabinet, nothing else",
                         out.newPaths == ["Studio › Paint cabinet › Drawer 1", "Studio › Paint cabinet › Drawer 2"]
                         && out.plan.newLocations.allSatisfy { $0.parent == .existing(cabinetID) })
            check.expect("Fill down: three paints in each drawer",
                         out.plan.items.filter { $0.path.last == "Drawer 1" }.count == 3 && out.plan.items.filter { $0.path.last == "Drawer 2" }.count == 3)
            check.expect("Brand and Size in notes", out.item("Ivory Black")?.notes == "Brand: Winsor & Newton\nSize: 37ml")
            check.expect("Link on its own line in notes (so it is tappable)",
                         out.item("Titanium White")?.notes == "Brand: Winsor & Newton\nSize: 200ml\nhttps://www.icloud.com/numbers/0000000000example")
        }
    }

    // MARK: 01 again

    check.section = "01 again"
    do {
        var scenario = Scenario(title: "01-simple-path.csv again   (re-import into the store left by the first run)", file: "01-simple-path.csv")
        scenario.existing = afterFirstImport
        if let out = run(scenario, directory: directory) {
            check.expect("0 items added", out.plan.items.isEmpty)
            check.expect("6 duplicates skipped", out.plan.skipCount(.alreadyExists) == 6 && out.plan.skipped.count == 6)
            check.expect("0 new spaces", out.plan.newLocations.isEmpty)
            check.expect("Import button would be disabled", !out.plan.hasAnythingToImport)
        }
    }

    // MARK: Field parsing (spec B6 examples)

    check.section = "Fields"
    print("")
    print(String(repeating: "=", count: 78))
    print("Field parsing: the examples from spec section B6, plus edge cases")
    print(String(repeating: "=", count: 78))

    let quantities: [(String, ImportQuantity)] = [
        ("3", .value(3, trailingText: nil)),
        ("3.0", .value(3, trailingText: nil)),
        ("x3", .value(3, trailingText: nil)),
        ("3x", .value(3, trailingText: nil)),
        ("×3", .value(3, trailingText: nil)),
        ("3 tubes", .value(3, trailingText: "tubes")),
        ("3 x 37ml", .value(3, trailingText: "x 37ml")),
        ("2.9", .value(2, trailingText: nil)),
        ("-4", .value(0, trailingText: nil)),
        ("1,000", .value(1000, trailingText: nil)),
        ("", .blank),
        ("about a dozen", .unreadable("about a dozen")),
        ("3/4", .unreadable("3/4")),
        ("5012345678900", .unreadable("5012345678900")),
    ]
    for (text, expected) in quantities {
        check.expect("Quantity \"\(text)\" → \(expected)", ImportFieldParsing.parseQuantity(text) == expected)
    }

    let dates: [(String, ImportDateOrder, ImportDay?)] = [
        ("2027-03-31", .dayFirst, day(2027, 3, 31)),
        ("31/03/2027", .dayFirst, day(2027, 3, 31)),
        ("31-03-2027", .dayFirst, day(2027, 3, 31)),
        ("31.03.2027", .dayFirst, day(2027, 3, 31)),
        ("31/03/27", .dayFirst, day(2027, 3, 31)),
        ("03/04/2027", .dayFirst, day(2027, 4, 3)),
        ("03/04/2027", .monthFirst, day(2027, 3, 4)),
        ("31/03/2027", .monthFirst, day(2027, 3, 31)),
        ("11/2026", .dayFirst, day(2026, 11, 30)),
        ("02/2028", .dayFirst, day(2028, 2, 29)),
        ("Nov 2026", .dayFirst, day(2026, 11, 30)),
        ("November 2026", .dayFirst, day(2026, 11, 30)),
        ("31 Mar 2027", .dayFirst, day(2027, 3, 31)),
        ("31-Mar-27", .dayFirst, day(2027, 3, 31)),
        ("March 31, 2027", .dayFirst, day(2027, 3, 31)),
        ("46477", .dayFirst, day(2027, 3, 31)),
        ("2027-03-31T00:00:00Z", .dayFirst, day(2027, 3, 31)),
        ("31/02/2027", .dayFirst, nil),
        ("soonish", .dayFirst, nil),
        ("12345678", .dayFirst, nil),
    ]
    for (text, order, expected) in dates {
        let label = expected.map(\.dayMonthYear) ?? "unreadable"
        check.expect("Date \"\(text)\" (\(order.rawValue)) → \(label)", ImportFieldParsing.parseDate(text, order: order) == expected)
    }

    check.expect("Path splits on > and ›", ImportFieldParsing.splitPath("Studio > Paint cabinet › Drawer 2", style: .arrows) == ["Studio", "Paint cabinet", "Drawer 2"])
    check.expect("Path splits on \" / \" but not a bare /",
                 ImportFieldParsing.splitPath("Office / A4/A3 paper", style: .slashes) == ["Office", "A4/A3 paper"])

    // MARK: Parser edge cases (spec B3)

    check.section = "Parser"
    let utf16 = Data([0xFF, 0xFE]) + "Item\tQty\r\nCafé\t2\r\n".data(using: .utf16LittleEndian)!
    let utf16Sheet = try? SpreadsheetParser.parse(data: utf16)
    check.expect("Excel \"Unicode Text\" (UTF-16 LE with BOM) reads", utf16Sheet?.rows == [["Item", "Qty"], ["Café", "2"]] && utf16Sheet?.delimiter == .tab)
    let cp1252Sheet = try? SpreadsheetParser.parse(data: Data([0x49, 0x74, 0x65, 0x6D, 0x2C, 0x51, 0x0A, 0x43, 0x61, 0x66, 0xE9, 0x2C, 0x32]))
    check.expect("Windows-1252 reads (Café)", cp1252Sheet?.rows == [["Item", "Q"], ["Café", "2"]])
    let oldMac = try? SpreadsheetParser.parse(text: "Item,Qty\rTape,1\rGlue,2")
    check.expect("Lone \\r line endings read", oldMac?.rows.count == 3)
    let inches = try? SpreadsheetParser.parse(text: "Item,Where\n2\" nails,Garage\n\"6\"\" ruler\",Desk")
    check.expect("Inch marks don't break quoting", inches?.rows == [["Item", "Where"], ["2\" nails", "Garage"], ["6\" ruler", "Desk"]])
    let unclosed = try? SpreadsheetParser.parse(text: "Item,Where\n\"Open quote,Garage\nTape,Desk")
    check.expect("An unclosed quote doesn't swallow the rest of the file", unclosed?.rows.count == 3)
    let ragged = try? SpreadsheetParser.parse(text: "a,b,c\nd,e,f\ng\nh,i\nj,k,l")
    check.expect("Short rows are padded to the widest", ragged?.rows[2] == ["g", "", ""] && ragged?.rows[3] == ["h", "i", ""])
    let hinted = try? SpreadsheetParser.parse(text: "sep=;\nItem;Qty\nTape;1")
    check.expect("Excel's sep=; line is honoured and dropped", hinted?.delimiter == .semicolon && hinted?.rows.count == 2)

    func failure(_ body: () throws -> ParsedSpreadsheet) -> SpreadsheetParseError? {
        do { _ = try body(); return nil } catch { return error as? SpreadsheetParseError }
    }
    check.expect("Over 5 MB is rejected", failure { try SpreadsheetParser.parse(data: Data(count: SpreadsheetParser.maxBytes + 1)) } == .tooLarge)
    let manyRows = String(repeating: "x\n", count: SpreadsheetParser.maxRows + 1)
    check.expect("Over 10,000 rows is rejected", failure { try SpreadsheetParser.parse(text: manyRows) } == .tooManyRows)
    check.expect("An .xlsx file gets the \"export as CSV\" message",
                 failure { try SpreadsheetParser.parse(data: Data([0x50, 0x4B, 0x03, 0x04, 0x14, 0x00])) } == .spreadsheetDocument)

    // MARK: Mapping and planner rules not covered by the files

    check.section = "Rules"
    var mapping = ImportMapping(hasHeaderRow: true, roles: [.locationLevel(1), .locationLevel(2), .itemName, .ignore])
    mapping.setRole(.locationPath, forColumn: 3)
    check.expect("Choosing full path clears the level columns", mapping.roles == [.ignore, .ignore, .itemName, .locationPath])
    mapping.setRole(.locationLevel(1), forColumn: 0)
    check.expect("Choosing a level clears the full path", mapping.roles == [.locationLevel(1), .ignore, .itemName, .ignore])
    mapping.setRole(.itemName, forColumn: 1)
    check.expect("Item name moves rather than doubling up", mapping.roles == [.locationLevel(1), .itemName, .ignore, .ignore])

    let descriptionSheet = [["Description", "Notes"], ["Tape", "sticky"]]
    check.expect("Description is the name when nothing else is", ImportAutoMapper.autoMap(rows: descriptionSheet).roles == [.itemName, .notes])
    let bothSheet = [["Item", "Description"], ["Tape", "sticky"]]
    check.expect("Description is notes when Item is the name", ImportAutoMapper.autoMap(rows: bothSheet).roles == [.itemName, .notes])
    let noHeading = [["Tape", "Garage"], ["Glue", "Shed"]]
    check.expect("Two columns with no headings: name must be chosen by hand", !ImportAutoMapper.autoMap(rows: noHeading).isReady)

    let limited: [[String]] = [["Item"]] + (1...30).map { ["Thing \($0)"] }
    var freeOptions = ImportOptions()
    freeOptions.remainingFreeCapacity = 18
    let freePlan = ImportPlanner.plan(rows: limited, mapping: ImportAutoMapper.autoMap(rows: limited), options: freeOptions)
    check.expect("Free plan: 18 left means 18 imported and 12 skipped", freePlan.items.count == 18 && freePlan.skipCount(.freeLimit) == 12)
    check.expect("Free plan wording",
                 freePlan.freeLimitMessage(remaining: 18, limit: 25) == "Free plan: 18 of 25 items left. 18 will be imported and 12 skipped.")

    let olderID = UUID(), newerID = UUID()
    let twins = ImportTreeSnapshot(nodes: [
        .init(id: newerID, name: "garage", parentID: nil, dateCreated: Date(timeIntervalSince1970: 200)),
        .init(id: olderID, name: "Garage", parentID: nil, dateCreated: Date(timeIntervalSince1970: 100), itemNames: ["TAPE"]),
    ])
    let twinRows = [["Item", "Location"], ["tape", " GARAGE "], ["Glue", "Garage"]]
    let twinPlan = ImportPlanner.plan(rows: twinRows, mapping: ImportAutoMapper.autoMap(rows: twinRows), existing: twins)
    check.expect("Matching ignores case and spaces, and picks the older of two same-named spaces",
                 twinPlan.newLocations.isEmpty && twinPlan.items.map(\.target) == [.existing(olderID)])
    check.expect("Duplicate check ignores case", twinPlan.skipped.map(\.name) == ["tape"] && twinPlan.skipCount(.alreadyExists) == 1)

    var keepDuplicates = ImportOptions()
    keepDuplicates.skipDuplicates = false
    let keptPlan = ImportPlanner.plan(rows: twinRows, mapping: ImportAutoMapper.autoMap(rows: twinRows), options: keepDuplicates, existing: twins)
    check.expect("Skip duplicates off imports them", keptPlan.items.count == 2)

    // Same name in the same place within one file: both kept (Joe, 12/11/2026),
    // even when the column that tells them apart is set to Ignore.
    let paints = [["Drawer", "Colour", "Brand"],
                  ["Drawer 1", "Titanium White", "Winsor & Newton"],
                  ["", "Titanium White", "Michael Harding"]]
    let paintPlan = ImportPlanner.plan(rows: paints, mapping: ImportAutoMapper.autoMap(rows: paints))
    check.expect("Two Titanium Whites from different brands are both kept (Brand ignored)",
                 paintPlan.items.count == 2 && paintPlan.skipped.isEmpty)
    let copied = [["Item", "Location"], ["Tape", "Garage"], ["Tape", "Garage"], ["tape ", "garage"]]
    let copiedPlan = ImportPlanner.plan(rows: copied, mapping: ImportAutoMapper.autoMap(rows: copied))
    check.expect("An exact copy of an earlier row is skipped", copiedPlan.items.count == 1 && copiedPlan.skipCount(.repeatedInFile) == 2)
    check.expect("Exact-copy wording", copiedPlan.warnings.contains("2 rows are exact copies of earlier rows and will be skipped"))

    let headingRows = [["Item", "Location"], ["", "Shed > Shelf"], ["Rake", ""], ["Hoe", ""]]
    let headingPlan = ImportPlanner.plan(rows: headingRows, mapping: ImportAutoMapper.autoMap(rows: headingRows))
    check.expect("A location-only heading row still sets the location for the rows below",
                 headingPlan.items.allSatisfy { $0.path == ["Shed", "Shelf"] } && headingPlan.items.count == 2)
    var noFill = ImportOptions()
    noFill.fillDown = false
    let noFillPlan = ImportPlanner.plan(rows: headingRows, mapping: ImportAutoMapper.autoMap(rows: headingRows), options: noFill)
    check.expect("Fill down off sends blank-location rows to Unsorted, and the unused Shed is not created",
                 noFillPlan.items.allSatisfy { $0.path == ["Unsorted"] } && noFillPlan.newLocations.map(\.name) == ["Unsorted"])

    // MARK: Totals

    print("")
    print(String(repeating: "=", count: 78))
    if check.failed.isEmpty {
        print("ALL \(check.passed) CHECKS PASSED")
    } else {
        print("\(check.failed.count) FAILED, \(check.passed) passed")
        for failure in check.failed { print("  FAIL  \(failure)") }
    }
    print(String(repeating: "=", count: 78))
    return check.failed.isEmpty
}

let arguments = CommandLine.arguments
let directory = URL(fileURLWithPath: arguments.count > 1 ? arguments[1] : "docs/import-test-files", isDirectory: true)
exit(runAll(directory: directory) ? 0 : 1)

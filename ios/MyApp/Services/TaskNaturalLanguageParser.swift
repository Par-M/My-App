import Foundation

struct ParsedTaskInput: Sendable {
    var title: String
    var category: String?
    var priority: TaskPriority
    var estimatedDuration: Int?
    var deadline: Date?
}

struct TaskNaturalLanguageParser {
    static func parse(_ rawText: String) -> ParsedTaskInput {
        let tokens = rawText.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        var category: String? = nil
        var priority: TaskPriority = .medium
        var duration: Int? = nil
        var deadline: Date? = nil
        var titleTokens: [String] = []
        
        let calendar = Calendar.current
        let now = Date()
        
        var i = 0
        while i < tokens.count {
            let token = tokens[i]
            let lower = token.lowercased()
            
            // Category parsing: #category
            if token.hasPrefix("#") && token.count > 1 {
                category = String(token.dropFirst())
                i += 1
                continue
            }
            
            // Priority parsing: !high, !medium, !low, !1, !2, !3
            if token.hasPrefix("!") && token.count > 1 {
                let p = String(token.dropFirst()).lowercased()
                if p == "high" || p == "1" || p == "urgent" {
                    priority = .high
                } else if p == "medium" || p == "med" || p == "2" {
                    priority = .medium
                } else if p == "low" || p == "3" {
                    priority = .low
                }
                i += 1
                continue
            }
            
            // Duration parsing: e.g. 45m, 1h, 30min, 90mins
            if let parsedDuration = parseDurationToken(lower) {
                duration = parsedDuration
                i += 1
                continue
            }
            
            // Date / Time parsing keywords: today, tomorrow
            if lower == "today" {
                deadline = calendar.startOfDay(for: now).addingTimeInterval(18 * 3600)
                i += 1
                continue
            } else if lower == "tomorrow" {
                if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) {
                    deadline = calendar.startOfDay(for: tomorrow).addingTimeInterval(18 * 3600)
                }
                i += 1
                continue
            }
            
            // Time parsing: "at 3pm", "at 15:00"
            if lower == "at", i + 1 < tokens.count, let parsedTime = parseTimeToken(tokens[i + 1].lowercased()) {
                let baseDate = deadline ?? calendar.startOfDay(for: now)
                var components = calendar.dateComponents([.year, .month, .day], from: baseDate)
                components.hour = parsedTime.hour
                components.minute = parsedTime.minute
                if let combined = calendar.date(from: components) {
                    deadline = combined
                }
                i += 2
                continue
            }
            
            titleTokens.append(token)
            i += 1
        }
        
        let cleanTitle = titleTokens.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return ParsedTaskInput(
            title: cleanTitle.isEmpty ? rawText : cleanTitle,
            category: category,
            priority: priority,
            estimatedDuration: duration,
            deadline: deadline
        )
    }
    
    private static func parseDurationToken(_ token: String) -> Int? {
        if token.hasSuffix("m") || token.hasSuffix("min") || token.hasSuffix("mins") {
            let numString = token.trimmingCharacters(in: CharacterSet.letters)
            if let mins = Int(numString), mins > 0 { return mins }
        }
        if token.hasSuffix("h") || token.hasSuffix("hr") || token.hasSuffix("hrs") || token.hasSuffix("hour") || token.hasSuffix("hours") {
            let numString = token.trimmingCharacters(in: CharacterSet.letters)
            if let hours = Double(numString), hours > 0 { return Int(hours * 60) }
        }
        return nil
    }
    
    private static func parseTimeToken(_ token: String) -> (hour: Int, minute: Int)? {
        let isPM = token.contains("pm")
        let isAM = token.contains("am")
        let clean = token.replacingOccurrences(of: "pm", with: "").replacingOccurrences(of: "am", with: "")
        let parts = clean.split(separator: ":")
        
        if parts.count == 1, let h = Int(parts[0]) {
            var hour = h
            if isPM && hour < 12 { hour += 12 }
            if isAM && hour == 12 { hour = 0 }
            return (hour, 0)
        } else if parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) {
            var hour = h
            if isPM && hour < 12 { hour += 12 }
            if isAM && hour == 12 { hour = 0 }
            return (hour, m)
        }
        return nil
    }
}

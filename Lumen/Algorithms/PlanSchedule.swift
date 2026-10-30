import Foundation

public enum PlanSchedule {
    public static func pending(_ documents: [HealthDocument]) -> [PendingPlanAction] {
        documents.filter { $0.kind == .plan && $0.status == .active }.flatMap { doc in
            doc.steps.filter { !$0.isDone }.map { PendingPlanAction(documentID: doc.id, planTitle: doc.title, step: $0) }
        }.sorted {
            if $0.step.calendarDate != $1.step.calendarDate { return ($0.step.calendarDate ?? .distantFuture) < ($1.step.calendarDate ?? .distantFuture) }
            return $0.id < $1.id
        }
    }
    public static func isOverdue(_ step: PlanStep, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard !step.isDone, let due = step.plannedDay.flatMap({ PlanDay.date($0, timeZone: calendar.timeZone) }) ?? step.dueDate else { return false }
        return calendar.compare(due, to: now, toGranularity: .day) == .orderedAscending
    }
}

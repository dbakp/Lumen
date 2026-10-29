#!/bin/zsh
set -eu
cd "${0:A:h:h}"
work_dir=$(mktemp -d /tmp/lumen-tests.XXXXXX)
trap 'rm -rf "$work_dir"' EXIT
swiftc -module-cache-path "$work_dir/cache" Lumen/Algorithms/DocumentBlocks.swift Lumen/Algorithms/TrendEvidence.swift Lumen/Algorithms/PlanSchedule.swift Lumen/Algorithms/PlanBuilder.swift Lumen/Algorithms/HealthHistorySummary.swift Lumen/Algorithms/HealthTotals.swift Lumen/Algorithms/ReminderPolicy.swift Lumen/Models/HealthModels.swift Lumen/Models/NutritionModels.swift Lumen/Models/ConversationModels.swift Lumen/Models/CompanionModels.swift Lumen/Services/HealthImportService.swift Tests/ImportTests.swift -o "$work_dir/import-tests"
"$work_dir/import-tests"

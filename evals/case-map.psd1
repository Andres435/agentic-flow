# Which eval tags a changed file should re-run. Data only: read by
# scripts/ticket/Select-EvalCases.ps1. When = -like globs against repo-relative,
# forward-slash paths. A file under evals/<case>/ maps to that case's own tags
# (from its prompt.md or case.yaml), so it needs no rule here. Tags the sample cases carry:
# start-ticket (start-feature, refuse-unconfigured), review (review-staged-secret), prep-pr.
@{
    Rules = @(
        @{ When = @('skills/start-ticket/*', 'skills/ticket-router/*', '_shared/ticket-plan-output.md', '_shared/engineering-decisions.md'); Tags = @('start-ticket') }
        @{ When = @('skills/complete-task/*', 'scripts/ticket/Close-Ticket.ps1'); Tags = @('complete-task') }
        @{ When = @('skills/review-changes/*', 'rules/security.mdc', '_shared/severity-and-output.md'); Tags = @('review') }
        @{ When = @('skills/implement/*'); Tags = @('implement') }
        @{ When = @('skills/prep-pr/*'); Tags = @('prep-pr') }
        @{ When = @('scripts/ticket/Assert-TicketArtifacts.ps1', 'scripts/ticket/manifest.schema.json'); Tags = @('start-ticket', 'complete-task') }
    )
}

import Tests.Language.ProgramPayloadFixtures.Rich
import Tests.Language.ProgramPayloadFixtures.Snapshot

open Tests.Language.ProgramPayloadFixtures.Rich

/-- Positive env imports only Rich; snapshots must not see attributed Neg* rows. -/
#snapshot_program_payloads richPayloadRows
#assert_rich_program_payload RichPayload

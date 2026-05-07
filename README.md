# PR #112 Screenshots

Evidence screenshots from v0.0.8 release re-test.

Raw URL pattern: https://raw.githubusercontent.com/oci-ai-incubations/ai-accelerator-starter-packs/screenshots/pr-112/pr-112/<path>

## Track 1 (BM.GPU4.8)

### round1-failed-LON
First Round 1 attempt in uk-london-1 AD-1; FAILED on infra apply due to OCI Out-of-Host-Capacity for VM.Standard.E5.Flex (initially mis-diagnosed as BUG-030, retracted). Wizard screenshots taken before apply.

### round1-failed-SJC
Second Round 1 attempt in us-sanjose-1 AD-1 with reverted v0.0.8 zip (no BUG-030 patch). Infra apply SUCCEEDED. App apply FAILED on patch_nim_operator_resources timeout — see BUG-032 (PVC RWO Multi-Attach race). Pack functionally works (smoke tests passed) but ORM apply state was FAILED.

### round1-retest-SJC (in progress)
Third Round 1 attempt with commit 215f5ee fixes (BUG-031 + BUG-032 patcher rewrite to runtime-readiness check). Pending — destroys in flight, fresh deploy queued.

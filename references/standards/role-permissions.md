# Deploy role permissions

Role prompts assign responsibilities. With `role_policy` enabled, `task_tree.py` and the step runner with `--tree` check the OS identity before writing a verdict. The runner also checks Tester identity before operating the UI. `--who` is a display label. The audit record stores the verified principal separately.

1. Allocate three distinct OS principals for Tester, Developer, and Lead. Use `whoami /user` on Windows to obtain the SID. On POSIX use `id -u` with a `uid:` prefix.
2. Store the mapping in a host-managed JSON file.

   ```json
   {"tester": "uid:1011", "developer": "uid:1012", "lead": "uid:1013"}
   ```

3. Set `"role_policy": "role-policy.json"` at the root of the task tree. Relative paths resolve from the tree directory. Protect the policy, tree configuration, and verifier. Limit writes to the controlled entry points. The Lead account reopens nodes. The Recorder reads evidence and writes a separate archive.

Enabling the policy requires fresh confirmations for active attempts. Historical signatures remain in the records.

| Role | Host access |
| --- | --- |
| Tester | Isolated test instance, assigned node, starting anchor, and current-round evidence writes. |
| Developer | Source, test evidence, diagnostic tools, and reviewer entry point. |
| Lead | Tasks, evidence, confirmation, and reopen entry points. |
| Recorder | Read-only acceptance materials and a separate writable archive. |

Restrict the Tester to test data and approved tools. Shared OS accounts require host isolation through tool sandboxing, separate execution identities, or a controlled write entry point. A process that can edit the tree directly can bypass the command-line checks.

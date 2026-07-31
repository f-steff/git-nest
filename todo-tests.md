# Unit test implementation tracker

## done

1. Create unit-tests/helper.sh (done)
2. Create unit-tests/mocks.sh (done)
3. Create unit-tests/run-all-tests.sh (done)
4. Create unit-tests/run-all-tests.bat (done)
5. Create unit-tests/unit-tests.md (done)
6. Update main runner with --unit-tests flag (done)
7. Update docs/maintainer.md link (done)
8. Update tests/tests.md with unit test paragraph (done)
9. unit-test_1000: path_is_relative_safe (done)
10. unit-test_1010: normalize_path, reject_backslash_path (done)
11. unit-test_1020: validate_clone_mode, validate_positive_integer (done)
12. unit-test_1200: shell_quote (done)
13. unit-test_1210: json_escape, json_string, json_row_object (done)
14. unit-test_1220: config_get, configured_clone_mode, effective_clone_mode (done)
15. unit-test_1300: repo_is_partial_clone, subproject_clone_mode (done)
16. unit-test_1400: default_target_branch, first_line, ticket_from_branch (done)
17. unit-test_1450: tree_survey_typelabel, list_reproducibility_code (done)
18. unit-test_1460: die, die_code, warn, notice, etc. (done)
19. unit-test_1470: sleep_ms, regex_escape, utc_now (done)
20. unit-test_1480: ensure_manifest, ensure_config, etc. (done)
21. unit-test_1500: repo_dirty, repo_has_dirty, remote_exists (done)
22. unit-test_1510: manifest_varname, section_kind, subproject_section (done)
23. unit-test_1520: redact_stream, json_array_from_lines (done)
24. unit-test_1530: safe_stale_path, etc. (done)
25. unit-test_1560: manifest_get_from_file, manifest_subprojects (done)
26. unit-test_1590: assert_safe_project_path, assert_no_case_collision (done)
27. unit-test_1600: current_branch, repo_root, etc. (done)
28. unit-test_1630: recovery_backup_dir, backup_timestamp, gitrepo_get (done)
29. unit-test_1640: infer_export_format, validate_export_format (done)
30. unit-test_1650: validate_config_value, is_gitignore_constant, etc. (done)
31. unit-test_1660: doctor_code_to_status, doctor_add_check (done)
32. unit-test_1670: gitattributes_has_guard, ensure_gitattributes_guard (done)
33. unit-test_1680: manifest_write_subproject, etc. (done)
34. unit-test_1690: emit_json_result, json_single_row_result (done)
35. unit-test_1700: repo_is_partial_clone with arg-diff mock (done)
36. unit-test_1710: resolve_commit with arg-diff mock (done)
37. unit-test_1720: manifest_preserved_keys (done)
38. unit-test_1730: effective_clone_mode (done)
39. unit-test_1990: coverage completeness check (done)
40. unit-tests/unit-tests.ini: deliberately untested functions catalogue (done)
41. Runner coverage output: 3-line summary + ini cross-ref (done)
42. docs/maintainer.md: testing philosophy section (done)

## todo

(empty -- all planned tasks completed)

## Stats

- Unit test files: 31
- Functions covered: 86/311 (27.7%)
- Deliberately untested: 225 (in unit-tests.ini)
- Unclassified: 0
- Integration tests: 56 (all passing)

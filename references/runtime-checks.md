# Runtime checks — why they silently do not run
`Abstract_Check_Runner::allow_runtime_checks()` is, verbatim:

```php
return ( $this->initialized_early || $this->runtime_environment->can_set_up() )
    && is_plugin_active( $this->get_plugin_basename() );
```

So the five runtime checks run **only** when both hold:

1. **`--require=<plugin-check>/cli.php` is passed, AFTER `plugin check`.**
   `cli.php` installs the object-cache drop-in that the runtime environment needs — but
   only when `CLI_Runner::is_plugin_check()` agrees, and that function tests
   `$_SERVER['argv'][1] === 'plugin' && $_SERVER['argv'][2] === 'check'`.
   `wp --require=… plugin check X` shifts argv by one, the test fails, and the bootstrap
   does nothing. Putting the global parameter in its natural place disables the exact
   thing it was passed for.

2. **The plugin under test is ACTIVE.** Copying it into `wp-content/plugins/` is not
   enough. `is_plugin_active()` is an unconditional `&&`.

**Neither failure is announced.** The run completes normally and reports fewer findings.

Verified empirically against Plugin Check 2.1.0 (a plugin enqueueing a 405 KB
render-blocking script):

| `--require` | plugin active | result |
|---|---|---|
| absent | yes | `Error: Check with the slug "enqueued_scripts_size" does not exist.` |
| before `plugin check` | yes | same error |
| before `plugin check` | no | same error |
| **after `plugin check`** | **yes** | `EnqueuedScriptsSize.ScriptSizeGreaterThanThreshold` ✓ |

### The cheap probe

When runtime checks are unavailable the runner does not quietly return nothing — it
**refuses the slug**. That makes a deterministic one-line test, no fixture required:

```sh
wp plugin check <slug> --require=<plugin-check>/cli.php --checks=enqueued_scripts_size --format=json
# "does not exist"  -> runtime checks are OFF, the run is partial
# anything else     -> runtime checks are live
```

`scripts/pcp-gate.sh` runs exactly this and refuses to describe a run as complete without it.

Note also that `wp plugin list-checks` lists all 34 slugs **regardless** — it reads the
repository, not the runner. It is not evidence that a check will run.

# history

Saves shell history and optionally variable bindings between shell sessions.

Allows the user to display history, and re-issue historic commands, made much
easier since the variable bindings are saved.

For ease History can be enabled in `~/.iex.exs` for example:

    Code.append_path("~/github/history/_build/dev/lib/history/ebin")
    History.initialize(history_limit: 200, scope: :local, show_date: true, colors: [index: :red])

Of course `Code.append_path` may not be required depending on how the project is imported.

The following options can be set:

    [
      scope: :local,
      history_limit: :infinity,
      hide_history_commands: true,
      show_date: true,
      save_bindings: true,
      colors: [
        index: :red,
        date: :green,
        command: :yellow,
        label: :red,
        variable: :green
      ]
    ]
    
:hide_history_commands  This will prevent all calls to History.* from been saved.

NOTE: History.x/1 is always hidden. Scope of `:global` will only hide them from output, otherwise they will not be saved.

`scope` can be one of `:local, :global` or a `node()` name

If `scope` is `:local` (the default) history will be active on all shells, even
those that are remotely connected, but the history for each shell will be
unique

If `scope` is `node()` (e.g. `:mgr@localhost`) history will only be active on that
shell

If `scope` is `:global` history will be shared between all shells. However the
saving of variable bindings will be disabled along with the date/time in
history

Furthermore, if a `scope` of `:global` is selected following kernel option must be
set, either directly as VM options or via an environment variable:

    export ERL_AFLAGS="-kernel shell_history enabled"

    --erl "-kernel shell_history enabled"

## Functions

### History.h()
```
Displays the entire history.
```

### History.h(val)
```
If the argument is a string it displays the history that contain or match
entirely the passed argument. If the argument is an integer it displays the
command at that index.
```

### History.x(idx)
```
Invokes the command at index 'i'.
```

### History.clear()
```
Clears the history and bindings. 
```

### History.initialize(opts)
```
Initializes the History app. Takes the following parameters:

      [
        scope: :local,
        history_limit: :infinity,
        show_date: true,
        save_bindings: true,
        colors: [
          index: :red,
          date: :green,
          command: :yellow,
          label: :red,
          variable: :green
        ]
      ]
```

### History.state()
```
Displays the current state:

    History version 2.0 is eenabled:
      Current history is 199 commands in size.
      Current bindings are 153 variables in size.
```

### History.clear()
```
Clears the history. If scope is  :global the IEx session needs restarting for
the changes to take effect.
```

### History.stop_clear()
```
Clears the history and stops the service. If scope is :global the IEx session needs 
restarting for the changes to take effect.
```

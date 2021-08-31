# history

Saves shell history and optionally variable bindings between shell sessions.

Allows the user to display history, and re-issue historic commands, made much
easier since the variable bindings are saved.

For ease History can be enabled in `~/.iex.exs` for example:

    Code.append_path("~/github/history/_build/dev/lib/history/ebin")
    History.initialize(history_limit: 200, scope: :local, show_date: true, colors: [index: :red])

The following options can be set:

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

### History.initialize(opts \\ [])
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

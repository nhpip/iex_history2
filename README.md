# history

Saves history between shell sessions. Allows the user to display history, and re-issue historic commands.

The following kernel option must be set, either directly as VM options or via an environment variable:

      export ERL_AFLAGS="-kernel shell_history enabled"
    
      --erl "-kernel shell_history enabled"

## Options

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
Clears the history. The IEx session needs restarting for the changes to take
effect.
```



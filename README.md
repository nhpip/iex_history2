# history

Saves history between shell sessions. Allows the user to display history, and re-issue historic commands.

The following kernel option must be set, either directly as VM options or via an environment variable:

      export ERL_AFLAGS="-kernel shell_history enabled"
    
      --erl "-kernel shell_history enabled"

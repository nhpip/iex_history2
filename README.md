# iex_history2 
Improved shell history withe variable binding persistance.

* Saves shell history between sessions.
* Saves the shell variable bindings between shell sessions.
* Navigation keys allow history traversal where multi-line pastes require a single key up/down.
* Shortcut functions permit search, pasting, re-evaluation and editing of items in history.
* Editing can be done in-situ or in a text editor.
* Shell variable bindings can be accessed outside of scope of the shell to assist in code debugging.
* Can be enabled and state shared globally, or on individual shell sessions.

`IExHistory2` can be enabled in `~/.iex.exs` for example:

    Code.append_path("~/github/iex_history2/_build/dev/lib/iex_history2/ebin")
    IExHistory2.initialize(history_limit: 200, scope: :local, show_date: true, colors: [index: :red])

Alternatively the project can be added as a `Mix` dependancy.

## Navigation Keys

```
    ctrl^u    - Move up through history.

    ctrl^k    - Move down through history.

    ctrl^e    - Allows the currently displayed item to be modified.

    ctrl^w    - Opens the currently displayed item in an editor.

    ctrl^[    - Reset navigation, returns to the prompt.
```
NOTE: To use `ctrl^w` the environment variable VISUAL must be set to point to the editor:
```
    export VISUAL="vim"
```

## Shortcut Search and Edit Functions
Key history navigation functions are automatically imported into the shell.
```
    iex> hl()             - Will list the entire history.

    iex> hl(val)          - Will list `val` entries from the start if val is positive, or from the end if negative.

    iex> hl(start, stop)  - Will list entries between `start` and `stop`.

    iex> hs(string)       -  Will list entries that match all or part the query string.

    iex> hx(pos)          - Will execute the expression at position `pos`.

    iex> hc(pos)          - Will copy the expression at position pos to the shell.

    iex> he(pos)          - Edit the expression in a text editor.

    iex> hb()             - Displays the current bindings.

    iex> hi()             - Summary

```
NOTE: To use `he/1` the environment variable VISUAL must be set to point to the editor:
```
    export VISUAL="vim"
```

### iex> hl()
Displays the entire history.
```
    iex> hl()
    1: 2023-09-01 17:29:27: time = Time.utc_now().second
    2: 2023-09-01 17:29:31: time = Time.utc_now().second
    3: 2023-09-01 17:29:36: time
    4: 2023-09-01 17:29:41: new_time
    5: 2023-09-01 17:50:10: Process.info self
    6: 2023-09-01 17:50:33: r = o
    7: 2023-09-01 17:52:36: Process.get(:iex_history)
```

### iex> hl(val)
If the argument is a positive integer it displays the command at that index.
If the argument is a negative number it displays the history that many items from the end.
```
    iex> hl(2)
    2: 2023-09-01 17:29:31: time = Time.utc_now().second
       
    iex> IExHistory2.h(-3)
    5: 2023-09-01 17:50:10: Process.info self
    6: 2023-09-01 17:50:33: r = o
    7: 2023-09-01 17:52:36: Process.get(:iex_history)
```

### iex> hl(start, stop)
Specify a range, the atoms :start and :stop can also be used.


### iex> hs(match)
Will search history for anything that matches the passed string.

    iex> hs("Applic")
    34: 2023-09-01 18:10:39: Application.put_env(:kernel, :shell_history, :disabled)
    41: 2023-09-01 18:11:30: Application.get_env(:kernel, :shell_history)
    48: 2023-09-01 18:14:02: Application.put_env(:kernel, :shell_history, 0)
    101: 2023-09-01 19:01:15: :rpc.call(:erlang.node(Process.group_leader()), Application, :put_env, [:kernel, :shell_history, :disabled])
    103: 2023-09-01 19:01:30: :rpc.call(:erlang.node(Process.group_leader()), Application, :put_env, [:kernel, :shell_history, :enabled])
 
### iex> hx(idx)
Invokes the command at index 'i'.
```
    iex> hl(114)
    114: 2023-09-01 19:30:14: Enum.count([1, 2, 3])
    
    iex> hx(114)
    3
```

### iex> hc(idx)
Copies the command at index 'i' and pastes it to the shell.
```
    iex> hl(114)
    114: 2023-09-01 19:30:14: Enum.count([1, 2, 3])
    
    iex> hc(114)
    :ok
    iex> Enum.count([1, 2, 3])
``` 

### iex> he(idx)
Usefull for large terms or pasted modules. Will open the historical item in a text editor, ensuring
the result is re-evaluated and returned to the shell.
```
    iex> he(114)
    .....
    .....
    {:ok, :changes_made}    
```
NOTE: To use `he/1` the environment variable VISUAL must be set to point to the editor:
```
    export VISUAL="vim"
```

### iex> hb()
Shows the variable bindings.

### iex> hi()
Status summary.


## Binding Functions
The functions IExHistory2.add_binding/2 and IExHistory2.get_binding/1 allows variables to be
set in a module that is invoked in the shell to be accessible in the shell.

### IExHistory2.add_binding/2

This helper function can be used when testing code (for example a module pasted
into the shell). It allows a variable to be set that will become available in
the shell. For example:
```
    defmodule VarTest do
      def set_me(var) do
        var = var * 2
        IExHistory2.add_binding(:test_var, var)
        var + 100
      end
    end

    iex> VarTest.set_me(7)

    iex> test_var
    14
```
The variable can be represented as an atom or string.

### IExHistory2.add_binding/2
The inverse of `add_binding/2`
It allows a variable that is set in the shell to be available in a module under test. For example:
```
    defmodule VarTest do
      def get_me(val) do
        if IExHistory2.get_binding(:path_to_use) == :path1 do
          val + 100
        else
          val + 200
        end
      end
    end

    iex> path_to_use = :path1
    :path1
    iex> VarTest.get_me(50)
    150
    iex> path_to_use = :path2
    :path2
    iex> VarTest.get_me(50)
```

Experimental varients of `add_binding/2` and get_binding/1` exist that takes an atom that
is the registered name of a shell process identifier.

## Misc Functions

### IExHistory2.initialize(opts)
Initializes the IExHistory2 app. Takes the following parameters:
```
      [
        scope: :local,
        history_limit: :infinity,
        prepend_identifiers: true,
        show_date: true,
        save_invalid_results: false,
        key_buffer_history: true,
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

### IExHistory2.clear()
Clears the history and bindings. If scope is  :global the IEx session needs restarting for the changes to take effect.

### IExHistory2.clear_history(range)
Clears the history only, if no argument all history is cleared, else history from 1 to value is cleared

### IExHistory2.clear_bindings()
Clears bindings only

### IExHistory2.unbind(vars)
Unbinds a variable or list of variables, varibales should be expressed as atoms

### IExHistory2.stop_clear()
Clears the history and bindings then stops the service. If scope is :global the IEx session needs restarting for the changes to take effect.

### IExHistory2.configuration()
Displays the current conifuration

### IExHistory2.save_config(filename)
Saves the configuration to filename

### IExHistory2.load_config(filename)
Loads the configuration from filename. 
NOTE: All changes may not be applied, to do this specify the filename in `IExHistory2.initialize/1` instead of a config keyword list

### IExHistory2.configure/2
Allows the following options to be changed, but not saved:
```
    :show_date
    :history_limit
    :hide_history_commands,
    :prepend_identifiers,
    :command_display_width,
    :save_invalid_results,
    :key_buffer_history,
    :save_bindings,
    :colors
 ```   
Examples:
```
    IExHistory2.configure(:colors, [index: :blue])
    IExHistory2.configure(:prepend_identifiers, true)
```

### IExHistory2.is_enabled?()
Returns true or false is IExHistory2 is enabled


## Configuration
The following options can be set:

    [
      scope: :local,
      history_limit: :infinity,
      hide_history_commands: true,
      prepend_identifiers: true,
      command_display_width: int,
      save_invalid_results: false,
      key_buffer_history: true,
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
    
`:hide_history_commands` This will prevent all calls to IExHistory2.* from been saved.

NOTE: `IExHistory2.x/1` is always hidden. Scope of `:global` will only hide them from output, otherwise they will not be saved.

`:save_invalid_results` If set to false, the default, commands that were evaluated incorrectly will not be saved.

`:key_buffer_history` If set to true will allow the user to scroll up `(ctrl+u)` or down `(ctrl+k)` through history. Unlike the standard up/down arrow history this is command based not line based. So pasting of a large structure will only require 1 up or down. This mechanism also saves commands that were not properly evaluated; however there is a buffer limit of 75 lines, although this can be changed by updating `@history_buffer_size` in `events_server.ex`. This will also not duplicate back to back identical commands.

`:prepend_identifiers`  If this is enabled it will prepend identifiers when a call to `x = IExHistory2(val)` is issued.

For example:
```
    enabled:
        iex> time = Time.utc_now().second
        14
        iex> new_time = IExHistory2.x(1)
        22

        iex> new_time
        22                  # New time is assigned to variable time
        iex> time
        13                  # However, the original date variable is unchanged

        iex> IExHistory2.h()
        1: 2023-09-01 17:13:13: time = Time.utc_now().second
        2: 2023-09-01 17:13:22: new_time =  time = Time.utc_now().second    # We see the binding to new_time

      disabled:
        iex> time = Time.utc_now().second
        43
        iex> new_time = IExHistory2.x(1)
        50

        iex> new_time       # New time is assigned to variable time
        50
        iex> time
        50                  # However, this time the original time variable has also changed

        iex> IExHistory2.h
        1: 2023-09-01 17:17:43: time = Time.utc_now().second
        2: 2023-09-01 17:17:50: time = Time.utc_now().second      # We do not see the binding to new_time
```

`:scope` can be one of `:local, :global` or a `node()` name

If `scope` is `:local` (the default) history will be active on all shells, even those that are remotely connected, but the history for each shell will be unique

If `scope` is `node()` (e.g. `:mgr@localhost`) history will only be active on that shell

If `scope` is `:global` history will be shared between all shells. However the saving of variable bindings will be disabled along with the date/time in history

Furthermore, if a `scope` of `:global` is selected following kernel option must be set, either directly as VM options or via an environment variable:
```
    export ERL_AFLAGS="-kernel shell_history enabled"

    --erl "-kernel shell_history enabled"
```

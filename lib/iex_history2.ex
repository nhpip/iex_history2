#
# MIT License
#
# Copyright (c) 2021 Matthew Evans
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#

defmodule IExHistory2 do
  @moduledoc """
  Improved shell history with variable binding persistance.

  * Saves shell history between VM/shell restarts.
  * Saves the shell variable bindings between VM/shell restarts.
  * Ability to paste (most) terms into the shell (pids, references etc are handled)
  * Navigation keys allow history traversal where multi-line pastes require a single key up/down.
  * Shortcut functions permit search, pasting, re-evaluation and editing of items in history.
  * Editing can be done in-situ or in a text editor.
  * Shell variable bindings can be set/get outside of scope of the shell to assist in application debugging.
  * Can be enabled and state shared globally, or on individual shell sessions.

  See section on `Initialization` and `Configuration` below.
  
  ## Short-cut Functions
    
      iex> hl()                     - list the entire history.
      
      iex> hl(val)                  - list `val` entries from the start if val is positive, or from the end if negative.
      
      iex> hl(start, stop)          - list entries between `start` and `stop`.
      
      iex> hs(string)               - list entries that match all or part of the query string.

      iex> hsi(string)              - case insensitive list entries that match all or part of the query string.

      iex> hsa(string, dist \\ 80)  - closest match list of entries, e.g "acr.to_str" == "Macro.to_string"
      
      iex> hx(pos)                  - execute the expression at position `pos`.
      
      iex> hc(pos)                  - copy the expression at position pos to the shell.
      
      iex> he(pos)                  - edit the expression in a text editor.
      
      iex> hb()                     - show the current bindings.
      
      iex> hi()                     - show summary / state

  **NOTE:** To use `he/1` the environment variable `EDITOR` must be set to point to your editor:
  
      export EDITOR="vim"

  ## Navigation Keys
          
  The application uses a different set of keys for navigation, and attempts to present multi-line 
  terms and other items as a single line:
  
      ctrl^u (21)   - move up through history (see below).
      
      ctrl^k (11)   - move down through history (see below).
      
      ctrl^h (08)   - allows the currently displayed item to be modified.
      
      ctrl^l (12)   - opens the currently displayed item in an editor.
              
      ctrl^[ (27)   - reset navigation, returns to the prompt.
              
  ### Text Editor
  
  To use `ctrl^e` the environment variable `EDITOR` must be set to your editor:
  
      export EDITOR=vim
  
  ### Standard Arrow Keys
  
  If you want to use the regular up / down arrow (and backspace) keys:
  
  1. Create the following file in your `HOME` directory:
  ```
      ~/.erlang_keymap.config
  ```
  ```
      [{stdlib,
        [{shell_keymap,
          \#{ normal => \#{ "\\e\[A" => none, "\\e\[B" => none } }
        }]
      }].
  ```
  
  2. Set the following environment variable:
  ```
      ERL_FLAGS='-config $HOME/.erlang_keymap.config'
  ``` 
     
  3. Add the following to the `IExHistory2` configuration:
  ```
      standard_arrow_keys: true
  ```  
      or   
  ```  
      IExHistory2.initialize(standard_arrow_keys: true, ....)
  ```        
         
  ## Examples
 
  Simple listing of last 9 items:
  
      iex hl(-9)  
      239: 2023-11-28 19:27:13: Ecto.Repo.Registry.lookup(CollectionServer.Server.Repo)
      240: 2023-11-28 19:27:27: Ecto.Repo.Registry.lookup(CollectionServer.Server.Repo.ReadOnly1)
      241: 2023-11-28 19:30:57: Ecto.Repo.Registry.all_running
      242: 2023-11-28 20:55:22: DevHelper.port_stats(peer_port: 5432, statistics: :send_cnt)
      243: 2023-11-28 20:55:34: Process.whereis(CSAdmin) |> :sys.get_status()
      244: 2023-11-28 20:55:53: Process.get(self())
      245: 2023-11-28 20:55:57: Process.get(CSAdmin)
      246: 2023-11-29 14:49:21: CollectionServer.Server.Repo.all(q1)
      247: 2023-11-29 17:48:21: %CollectionServer.FileSystem.Node{}

  Partial match:
  
      iex> hsa("Prcess.")
      7: 90% 2023-11-12 16:29:03: c = fn -> {dict, _} = Process.info(pid, :dictionary); dict[:request_user] end
      8: 90% 2023-11-12 16:29:37: c = fn -> {dict, _} = Process.info(pid, :dictionary) end
      20: 90% 2023-11-26 16:32:11: Process.get(:yyy)
      21: 90% 2023-11-26 22:11:50: Process.info(pid(0,619,0))
      208: 90% 2023-11-28 14:19:23: Process.whereis(CollectionServer.Server.ReadOnly1)
      209: 90% 2023-11-28 14:19:34: Process.whereis(CollectionServer.Server.ReadOnly1) |> Process.info
      210: 90% 2023-11-28 14:20:02: Process.whereis(CollectionServer.Server.ReadOnly1) |> Process.info() |> Keyword.get(:links)
      211: 90% 2023-11-28 14:20:14: Process.whereis(CollectionServer.Server.Repo) |> Process.info() |> Keyword.get(:links)

  ## Special Functions

      iex> IExHistory2.add_binding(var, val)
      
      iex> IExHistory2.get_binding(var)
      
      iex> IExHistory2.clear_history()
      
      iex> IExHistory2.clear_bindings()
          
  The functions `IExHistory2.add_binding/2` and `IExHistory2.get_binding/1` allows variables that
  are bound in the shell to be accessible in an external module that has been loaded into the shell and vice versa.
      
      defmodule VarTest do      
        def get_me(val) do
          if IExHistory2.get_binding(:path_to_use) == :path1 do
            result = val + 100
            IExHistory2.add_binding(:result_var, %{path: :path1, result: result})
            result
          else
            result = val + 200
            IExHistory2.add_binding(:result_var, %{path: :path2, result: result})
            result
          end
        end
      end
          
      iex> path_to_use = :path1
      :path1
      iex> VarTest.get_me(50)
      150
      iex> result_var
      %{path: :path1, result: 150}
      
      iex> path_to_use = :path2
      :path2
      iex> VarTest.get_me(50)
      250
      iex> result_var
      %{path: :path2, result: 250}

  The complimentary functions `add_binding/3` and `get_binding/2` that take a shell pid or registered name allowing
  the user to debug applications.
  
      defmodule VarTest do
        def get_me(val) do
          if IExHistory2.get_binding(:path_to_use, :myshell) == :path1 do
            result = val + 100
            IExHistory2.add_binding(:result_var, %{path: :path1, result: result}, :myshell)
            result
          else
            result = val + 200
            IExHistory2.add_binding(:result_var, %{path: :path2, result: result}, :myshell)
            result
          end
        end
      end

      iex> spawn(fn -> VarTest.get_me(100) end)
      #PID<0.1557.0>
      %{path: :path2, result: 300}
      iex> result_var
      %{path: :path2, result: 300}
            
  See also `IExHistory2.register/1`.
   
  ## Configuration
    
  The following options can be set either as a keyword list in `.iex.exs` (a sample file is 
  included in the `github` repository):

      [
        colors: [
          index: :red,
          date: :green,
          command: :yellow,
          label: :red,
          variable: :green,
          binding: :cyan
        ],
        command_display_width: 150,
        hide_history_commands: true,
        history_limit: :infinity,
        import: true,
        key_buffer_history: true,
        navigation_keys: [
          up: 21,
          down: 11,
          editor: 12,
          modify: 8,
          abandon: 27,
          enter: 13
        ],
        standard_arrow_keys: false,
        paste_eval_regex: ["#Reference", "#PID", "#Function", "#Ecto.Schema.Metadata", "#Port"],
        prepend_identifiers: true,
        save_bindings: true,
        save_invalid_results: false,
        scope: :local,
        show_date: true
      ]

  Or in `config/runtime.exs`:
 
      config :your_app, IExHistory2,
        scope: :local,
        history_limit: :infinity,
        paste_eval_regex: [],
        import: true,
        ...
   
  ### Settings
        
  To import short-cut functions set `import:` to true.
  
      import: true
      
  One issue with the current shell is the inconsistent ability to paste large terms into
  the shell. Types such as process ids and references (`#PID<0.1234.0>`) cause the evaluator to fail. 
  `IExHistory2` will attempt to recognize and parse such terms during evaluation. 
  
  Currently process ids, references, anonymous functions, ports and `#Ecto.Schema.Metadata` are 
  supported by default. Additional terms can be added:
  
      paste_eval_regex: ["#SpecialItem1", "#NewObject"]
          
  This toggle true/false for calls to `IExHistory2.*` (and imports) from been saved.
        
      hide_history_commands: true 
      
  If set to false, the default, commands that were evaluated incorrectly will not be saved.
  
      save_invalid_results: false 

  If set to true will allow the user to scroll up (ctrl+u) or down (ctrl+k) through history.
      
      key_buffer_history: true
      
  Unlike the standard up/down arrow history where the up-arrow key has to be pressed multiple times to 
  traverse a large term, `IExHistory2` only requires a single up/down key, and the entire term can then
  be edited.
  
  The default navigation keys are defined above, but can be changed to any reasonable value. Please be aware
  that certain key are reserved by the runtime and can not be used. The values should be set to decimal, the 
  example below sets opening the editor from `ctrl^l` to `ctrl^e`
  
      navigation_keys: [editor: 5]
    
  To use standard up/down arrow keys set:
  
      standard_arrow_keys: true
    
  If this is enabled it will prepend identifiers when a call to `x = hx(val)` is issued.

      prepend_identifiers: true
      
  Example, enabled:
   
      iex> time = Time.utc_now().second
      14
      iex> new_time = hx(1)
      22

      iex> new_time
      22                  # New time is assigned to variable time
      iex> time
      13                  # However, the original date variable is unchanged

      iex> hl()
      1: 2021-09-01 17:13:13: time = Time.utc_now().second
      2: 2021-09-01 17:13:22: new_time =  time = Time.utc_now().second    # We see the binding to new_time

  Disabled:
  
      iex> time = Time.utc_now().second
      43
      iex> new_time = hx(1)
      50

      iex> new_time       # New time is assigned to variable time
      50
      iex> time
      50                  # However, this time the original time variable has also changed

      iex> hl()
      1: 2021-09-01 17:17:43: time = Time.utc_now().second
      2: 2021-09-01 17:17:50: time = Time.utc_now().second      # We do not see the binding to new_time


  `scope:` can be one of `:local, :global `or a `node name`

  * `:local` (the default) history will be active on all shells, even those that are remotely connected, but the history for each shell will be unique.

  * `node_name`i.e. (e.g. `:mgr@localhost`) history will only be active on that shell.

  * `:global` history will be shared between all shells. However the saving of variable bindings will be disabled.

  ## Initialization
  
  ### Using `.iex.exs`
  
  It is recommended to configure and start using `.iex.exs`, for  example:
  
      IExHistory2.initialize(history_limit: :infinity,
                             scope: :local, 
                             paste_eval_regex: ["#Extra"], 
                             show_date: true, 
                             colors: [index: :red])
  
  ### As part of another application
   
  Add to `mix.exs` as a dependency: 
  
      {:iex_history2, "~> 5.3"}
  
  Or:
  
      {:iex_history2, github: "nhpip/iex_history2", tag: "5.3.0"},
          
  Add the configuration to your application `config/runtime.exs`. For example:
  
      config :iex_history2,
        history_limit: 1234,
        import: true,
        scope: :local, 
        paste_eval_regex: ["#Extra"], 
        show_date: true, 
        colors: [index: :red]
      
  When you connect your shell call `IExHistory2.initialize/0` (in `.iex.exs` or as a standalone call):
  
      IExHistory2.initialize()
  
  """

  @version "5.3"
  @module_name String.trim_leading(Atom.to_string(__MODULE__), "Elixir.")
  @exec_name String.trim_leading(Atom.to_string(__MODULE__) <> ".hx", "Elixir.")

  @shell_imports [hl: 0, hl: 1, hl: 2, hs: 1, hsi: 1, hsa: 1,
                  hsa: 2, hc: 1, hx: 1, hb: 0, hi: 0, he: 1]
  @exclude_from_history_imports ["hc(", "hl(", "hs(", "hsi(", "hsa(", "hx(", "hb(", "hi(", "he(",
                                  "hc ", "hl", "hs ", "hsi ", "hsa ", "hx ", "hb ", "hi ", "he "]
  @exclude_from_history_basic (for fun <- @exclude_from_history_imports do 
                                    mod = Atom.to_string(__MODULE__) 
                                          |> String.replace("Elixir.", "")
                                    "#{mod}.#{fun}"
                               end)     
  @exclude_from_history_methods @exclude_from_history_imports ++ @exclude_from_history_basic
  
  @default_paste_eval_regex ["#Reference", "#PID", "#Function", "#Ecto.Schema.Metadata", "#Port"]
  
  @history_up_key 21 # ctrl+u (try "\e[A" if overriding default)
  @history_down_key 11  # ctrl+k (try "\e[B" if overriding default)
  @editor_key 12 # ctrl+l
  @modify_key 08 # ctrl+h
  @abandon_key 27 # ctrl+[ or esc(ape)
  @enter_key 13
  
  @standard_arrow_keys [up: "\e[A", down: "\e[B", modify: "\d"]
  
  @alive_prompt "%prefix(%node)%counter>"
  @default_prompt "%prefix(%counter)>"
  
  @default_navigation_keys [up: @history_up_key,
                            down: @history_down_key,
                            editor: @editor_key,
                            modify: @modify_key,
                            abandon: @abandon_key,
                            enter: @enter_key]
  
  @default_width 150
  @default_colors [index: :red, date: :green, command: :yellow, label: :red, variable: :green, binding: :cyan]
  @default_config [
    scope: :local,
    history_limit: :infinity,
    hide_history_commands: true,
    standard_arrow_keys: false,
    prepend_identifiers: true,
    show_date: true,
    save_bindings: true,
    command_display_width: @default_width,
    paste_eval_regex: @default_paste_eval_regex,
    navigation_keys: @default_navigation_keys,
    import: true,
    save_invalid_results: false,
    key_buffer_history: true,
    colors: @default_colors
  ]

  alias IExHistory2.Events
  alias IExHistory2.Bindings
  alias IExHistory2.Events.Server
  
  @doc """
  Initializes the IExHistory2 app. Takes the following parameters:

    [
      scope: :local,
      history_limit: :infinity,
      hide_history_commands: true,
      prepend_identifiers: true,
      key_buffer_history: true,
      command_display_width: :int,
      save_invalid_results: false,
      show_date: true,
      import: true,
      paste_eval_regex: [],
      navigation_keys: [up: 21, down: 11, ...],
      standard_arrow_keys: false,
      save_bindings: true,
      colors: [
        index: :red,
        date: :green,
        command: :yellow,
        label: :red,
        variable: :green
      ]
    ]

  Alternatively a filename can be given that was saved with `IExHistory2.save_config()`

  `scope` can be one of `:local, :global` or a `node()` name
  """
  @spec initialize(list()) :: list() | atom()
  def initialize(config_or_filename \\ []) do
    config = do_load_config(config_or_filename)
             |> Keyword.put_new(:scope, Events.get_scope(config_or_filename)) 

    if history_configured?(config) && not is_enabled?() do
      :dbg.stop()
      new_config = init_save_config(config)
      inject_command("IEx.configure(colors: [syntax_colors: [atom: :black]])")

      if Keyword.get(new_config, :import),
        do: inject_command("import IExHistory2, only: #{inspect(@shell_imports)}")

      Events.initialize(new_config)
      |> set_enabled()
      |> present_welcome()
      |> finalize_startup()
    else
      if is_enabled?(), 
        do: :history_already_enabled,
        else: :history_disabled
    end
  end
  
  @spec start(list()) :: {:ok, pid()}
  def start(config \\ default_config()) do 
    IExHistory2.Supervisor.start_link(config)
  end

  @doc false
  def start(_, _) do 
    Application.get_all_env(:iex_history2)
    |> IExHistory2.Supervisor.start_link()
  end
  
  @doc false
  def start_link(config) do
    init_save_config(config)
    |> Keyword.put(:running_mode, :supervisor)
    |> Events.initialize()
    |> Keyword.get(:events_server_pid)
  end
  
  @doc false
  def child_spec(config) do
    %{
        id: Keyword.get(config, :id, __MODULE__),
        start: {__MODULE__, :start_link, [config]},
        type: Keyword.get(config, :type, :worker),
        restart: :permanent,
        shutdown: 5000
    }
  end
    
  @doc false
  def iex_parse("iex_history2_no_evaluation", _opts, buffer) do
    receive do
      {:history2, m} -> {:ok, m, buffer}
    after 
      0 -> {:ok, nil, buffer}
    end 
  end
    
  @doc false
  def iex_parse(expr, opts, buffer) do
    handle_iex_break(expr)  
    try do 
       case IEx.Evaluator.parse(expr, opts, buffer) do        
        {:ok, {:def, _, _} = ast, _rsp} ->
          set_prompts(:normal)
          Server.iex_parse(Macro.to_string(ast))
          |> iex_parse(opts, "")
          
        {:ok, ast, rsp} ->
          Process.delete(:iex_history2_start)
          set_prompts(:normal)
          Server.save_expression(Macro.to_string(ast))
          {:ok, ast, rsp}
                    
        {:incomplete, rsp} -> 
          start_time = Process.get(:iex_history2_start, System.monotonic_time())
          if System.convert_time_unit(System.monotonic_time() - start_time, :native, :millisecond) > 1000 do
            set_prompts(:incomplete)
            {:incomplete, rsp}
          else   
            Process.put(:iex_history2_start, System.monotonic_time())
            set_prompts(:paste)
            {:incomplete, rsp}
          end
      end  
    rescue
      e -> 
        if Keyword.get(opts, :exception) && Keyword.get(opts, :last_expr) == expr && buffer == "" do
          set_prompts(:normal)
          reraise(e, __STACKTRACE__)
        else   
          opts = Keyword.delete(opts, :last_expr) 
          |>  Keyword.delete(:exception)
          set_prompts(:paste)
          send_for_parsing(expr, buffer)
          |> iex_parse([{:exception, true}, {:last_expr, expr} | opts], "")
      end
    end
  end
  
  @doc """
  Displays the current configuration.
  """
  def configuration() do
    cfg = Process.get(:history_config, [])
    nav_keys = Keyword.get(cfg, :navigation_keys, [])
               |> Enum.map(fn {k, v} when is_bitstring(v)-> 
                                  {k, to_string(v)} 
                               kv -> kv
                  end)      
    Keyword.put(cfg, :navigation_keys, nav_keys)
    |> Keyword.delete(:compiled_paste_eval_regex)
  end
  
  @doc """
  Displays the default configuration.
  """
  def default_config(),
    do: @default_config

  @doc """
  Displays the entire history.
  """
  def hl() do
    is_enabled!()

    query_search(fn ->  Events.get_history() end)
  end

  @doc """
  Displays the entire history from the most recent entry back (negative number),
  or from the oldest entry forward (positive number)
  """
  @spec hl(integer()) :: nil
  def hl(val) when val < 0 do
    is_enabled!()

    query_search(fn ->  Events.get_history_item(val) end)
  end

  def hl(val) when val > 0 do
    is_enabled!()

    query_search(fn ->  Events.get_history_items(1, val) end)
  end

  @doc """
  Specify a range.
  
    iex> hl(10, 15)
    
  """
  @spec hl(integer(), integer()) :: nil
  def hl(start, stop) do
    is_enabled!()

    query_search(fn ->  Events.get_history_items(start, stop) end)
  end

  @doc """
  Returns the list of expressions where all or part of the string matches.

  The original expression does not need to be a string.
  """
  @spec hs(String.t()) :: nil
  def hs(match) do
    is_enabled!()

    query_search(fn ->  Events.search_history_items(match, :exact) end)
  end

  @doc """
  A case insensitive search the list of expressions where all or part of the string matches.

  The original expression does not need to be a string.
  """
  @spec hsi(String.t()) :: nil
  def hsi(match) do
    is_enabled!()

    query_search(fn ->  Events.search_history_items(match, :ignore_case) end)
  end
  
  @doc """
  Like `hsa/1` a case insensitive search, but also adds a closeness element to the search.

  It uses a combination of Myers Difference and Jaro Distance to get close to a match. The
  estimated closeness is indicated in the result with a default range of > 80%.
  This can be set by the user.
  
  For large histories this command may take several seconds.
  
  The original expression does not need to be a string.
  
      iex> hsa("get_stte")
      446: 92% 2024-02-04 23:27:16: :sys.get_state(Process.whereis(IExHistory2.Events.Server))
      465: 92% 2024-02-05 00:57:04: :sys.get_state(Process.whereis(IExHistory2.Events.Server))
      467: 92% 2024-02-05 00:57:38: :sys.get_state(Process.whereis(IExHistory2.Events.Server))
      468: 92% 2024-02-05 00:58:25: :sys.get_state(Process.whereis(IExHistory2.Events.Server))
      470: 92% 2024-02-05 00:59:17: :sys.get_state(Process.whereis(Server))
      30: 83% 2024-02-03 20:22:41: :code.get_object_code(Types.UUID)

  """
  @spec hsa(String.t(), integer()) :: nil
  def hsa(match, closeness \\ 80) do
    is_enabled!()

    query_search(fn ->  Events.search_history_items(match, :approximate, closeness) end)
  end
  
  @doc """
  Invokes the command at index 'i'.
  """
  @spec hx(integer()) :: any()
  def hx(i) do
    is_enabled!()

    try do
      Events.execute_history_item(i)
    catch
      _, {:badmatch, nil} -> {:error, :not_found}
      :error, %CompileError{description: descr} -> {:error, descr}
      error, rsn -> {error, rsn}
    end
  end

  @doc """
  Copies the command at index 'i' and pastes it to the shell.
  """
  @spec hc(integer()) :: any()
  def hc(i) do
    is_enabled!()
    
    query_search(fn -> Events.copy_paste_history_item(i) end)
  end

  @spec he(integer()) :: any()
  def he(i) do
    is_enabled!()

     query_search(fn ->  Events.edit_history_item(i) end)
  end

  @doc """
  Show the variable bindings.
  """
  def hb(),
    do: Bindings.display_bindings()

  @doc """
  Displays the current state:

      IExHistory2 version 5.3 is enabled:
        Current history is 199 commands in size.
        Current bindings are 153 variables in size.
  """
  def hi(),
    do: state()

  ###
  # Backwards compatibility
  ###
  @doc false
  def h(), do: hl()
  @doc false
  def h(val), do: hl(val)
  @doc false
  def h(start, stop), do: hl(start, stop)
  @doc false
  def c(val), do: hc(val)
  @doc false
  def x(val), do: hx(val)
  @doc false  
  def save_binding(val), do: add_binding(val)
  @doc false
  def save_binding(var, val), do: add_binding(var, val)
    
  @doc """
    Clears the history and bindings. If `scope` is `:global`
    the IEx session needs restarting for the changes to take effect.
  """
  def clear() do
    Events.clear()
    Bindings.clear()

    if IExHistory2.configuration(:scope, :local) == :global,
      do: IO.puts("\n#{IO.ANSI.green()}Please restart your shell session for the changes to take effect")

    :ok
  end

  @doc """
  Clears the history only. If `scope` is `:global`
  the IEx session needs restarting for the changes to take effect. If a value is passed it will clear that many history
  entries from start, otherwise the entire history is cleared.
  """
  def clear_history(val \\ :all) do
    Events.clear_history(val)

    if IExHistory2.configuration(:scope, :local) == :global && val == :all,
      do: IO.puts("\n#{IO.ANSI.green()}Please restart your shell session for the changes to take effect")

    :ok
  end

  @doc """
  Clears the bindings.
  """
  def clear_bindings() do
    Bindings.clear()
    :ok
  end

  @doc """
  Clears the history and bindings then stops the service. If `scope` is ` :global` the IEx session needs restarting for the changes to take effect.
  """
  def stop_clear() do
    Events.stop_clear()
    Bindings.stop_clear()

    if IExHistory2.configuration(:scope, :local) == :global,
      do: IO.puts("\n#{IO.ANSI.green()}Please restart your shell session for the changes to take effect")

    :ok
  end

  @doc """
  Returns `true` or `false` depending on if history is enabled.
  """
  def is_enabled?() do
    Process.get(:history_is_enabled, false)
  end

  @doc """
  Returns the current shell bindings as a keyword list.
  """
  def get_bindings() do
    Bindings.get_bindings()
  end

  @doc """
  The functions `IExHistory2.add_binding/2` and `IExHistory2.get_binding/1` allows variables that
  are bound in the shell to be accessible in a module and vice-versa.
  
  In this example the module was pasted into the shell.
   
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
      250
      
  The variable can be represented as an atom or string.      
  """
  @spec get_binding(atom() | String.t()) :: any()
  def get_binding(var) when is_bitstring(var) do
    get_binding(String.to_atom(var))
  end

  def get_binding(var) do
    try do
      Bindings.get_binding(var)
    rescue
    _ -> raise("undefined variable #{var}")  
    end
  end
  
  @doc """
  Same as `get_binding/2`, but `name` is the registered name of your shell. Useful 
  for debugging applications.
  
      defmodule VarTest do
        def get_me(val) do
          if IExHistory2.get_binding(:path_to_use, :myshell) == :path1 do
            result = val + 100
            IExHistory2.add_binding(:result_var, %{path: :path1, result: result}, :myshell)
            result
          else
            result = val + 200
            IExHistory2.add_binding(:result_var, %{path: :path2, result: result}, :myshell)
            result
          end
        end
      end

      iex> IExHistory2.register(:myshell)
      true
      iex> spawn(fn -> VarTest.get_me(100) end)
      #PID<0.1557.0>
      %{path: :path2, result: 300}
      iex> result_var
      %{path: :path2, result: 300}
            
  See also `IExHistory2.register/1`.
  """
  @spec get_binding(atom() | String.t(), atom() | pid()) :: any()  
  def get_binding(var, name) when is_bitstring(var) do
    get_binding(String.to_atom(var), name)
  end
  
  def get_binding(var, name) do
    try do
      Bindings.get_binding(var, name)
    rescue
    _ -> raise("undefined variable #{var}")  
    end
  end
  
  @doc """
  See `IExHistory2.get_binding/1`.
  
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
        
  The variable can be represented as an atom or string.      
  """
  @spec add_binding(atom() | String.t(), any()) :: :ok
  def add_binding(var, value) do
    inject_command("#{var} = #{inspect(value, limit: :infinity, printable_limit: :infinity)}")
    value
  end
  
  @doc """
  Same as `add_binding/2`, but `name` is the registered name of a shell.
  
  See also `register/1` and `get_binding/2`
  """
  @spec add_binding(atom() | String.t(), any(), atom() | pid()) :: :ok
  def add_binding(var, value, name) do
    inject_command("#{var} = #{inspect(value, limit: :infinity, printable_limit: :infinity)}", name)
    value
  end

  @doc false
  def add_binding(value) do
    inject_command("#{inspect(value, limit: :infinity, printable_limit: :infinity)}")
    value
  end
  
  @doc """
  Registers the shell under the name provided.
  """
  @spec register(atom()) :: :ok
  def register(name) do
    Process.register(self(), name)  
  end
  
  @doc false
  def eval_on_shell(value, name) do
    inject_command("#{inspect(value, limit: :infinity, printable_limit: :infinity)}", name)
    :ok
  end
    
  @doc false
  def eval_on_shell(var, value, name) do
    inject_command("#{var} = #{inspect(value, limit: :infinity, printable_limit: :infinity)}", name)
    :ok
  end
  
  @doc """
  Unbinds a variable or list of variables (specify variables as atoms, e.g. foo becomes :foo).
  """
  def unbind(vars) when is_list(vars), do: Bindings.unbind(vars)
  def unbind(var), do: unbind([var])

  @doc false
  def save_config(filename) do
    data = :io_lib.format("~p.", [raw_configuration()]) |> List.flatten()
    :file.write_file(filename, data)
  end

  @doc false
  def load_config(filename) do
    config = do_load_config(filename)
    Process.put(:history_config, config)
    config
  end

  @doc """
  Allows the following options to be changed, but not saved:
      :show_date
      :history_limit
      :hide_history_commands,
      :prepend_identifiers,
      :command_display_width,
      :save_invalid_results,
      :key_buffer_history,
      :colors

  Examples:
      IExHistory2.configure(:colors, [index: :blue])
      IExHistory2.configure(:prepend_identifiers, true)
  """
  @spec configure(atom(), any) :: atom
  def configure(kry, val)

  def configure(:show_date, value) when value in [true, false] do
    new_config = List.keyreplace(configuration(), :show_date, 0, {:show_date, value})
    Process.put(:history_config, new_config)
    configuration()
  end

  def configure(:command_display_width, value) when is_integer(value) do
    new_config = List.keyreplace(configuration(), :command_display_width, 0, {:command_display_width, value})
    Process.put(:history_config, new_config)
    configuration()
  end

  def configure(:hide_history_commands, value) when value in [true, false] do
    new_config = List.keyreplace(configuration(), :hide_history_commands, 0, {:hide_history_commands, value})
    Events.send_message({:hide_history_commands, value})
    Process.put(:history_config, new_config)
    configuration()
  end

  def configure(:key_buffer_history, value) when value in [true, false] do
    new_config = List.keyreplace(configuration(), :key_buffer_history, 0, {:key_buffer_history, value})
    Events.send_message({:key_buffer_history, value})
    Process.put(:history_config, new_config)
    configuration()
  end

  def configure(:save_invalid_results, value) when value in [true, false] do
    new_config = List.keyreplace(configuration(), :save_invalid_results, 0, {:save_invalid_results, value})
    Events.send_message({:save_invalid_results, value})
    Process.put(:history_config, new_config)
    configuration()
  end

  def configure(:prepend_identifiers, value) when value in [true, false] do
    new_config = List.keyreplace(configuration(), :prepend_identifiers, 0, {:prepend_identifiers, value})
    Events.send_message({:prepend_identifiers, value})
    Process.put(:history_config, new_config)
    configuration()
  end

  def configure(:history_limit, value) when is_integer(value) or value == :infinity do
    new_config = List.keyreplace(configuration(), :history_limit, 0, {:history_limit, value})
    new_value = if value == :infinity, do: Events.infinity_limit(), else: value
    Events.send_message({:new_history_limit, new_value})
    Process.put(:history_config, new_config)
    configuration()
  end

  def configure(:colors, keyword_list) do
    new_colors = Keyword.merge(configuration(:colors, []), keyword_list)
    new_config = List.keyreplace(configuration(), :colors, 0, {:colors, new_colors})
    Process.put(:history_config, new_config)
    configuration()
  end

  @doc false
  def get_color_code(for), do: Kernel.apply(IO.ANSI, configuration(:colors, @default_colors)[for], [])

  @doc false
  def get_log_path() do
    filename = :filename.basedir(:user_cache, ~c"erlang-history") |> to_string()
    File.mkdir_p!(filename)
    filename
  end

  @doc false
  def state() do
    IO.puts("IExHistory2 version #{IO.ANSI.red()}#{@version}#{IO.ANSI.white()} is enabled:")
    IO.puts("  #{Events.state()}.")
    IO.puts("  #{Bindings.state()}.")
  end
  
  @doc false
  def my_real_node() do
    Kernel.node(Process.group_leader())
  end
  
  @doc false
  def module_name(),
    do: @module_name

  @doc false
  def exec_name(),
    do: @exec_name

  @doc false
  def exclude_from_history() do
    @exclude_from_history_methods
  end

  @doc false
  def configuration(item, default) do
    Keyword.get(configuration(), item, default)
  end
  
  @doc false
  def persistence_mode(:local) do
    my_node = my_real_node()
    %{init: true, scope: :local, node: my_node}
  end

  @doc false
  def persistence_mode(:global) do 
    my_node = node()
    %{init: true, scope: :global, node: my_node}
  end
  
  @doc false
  def persistence_mode(node) when is_atom(node) do
    my_node = my_real_node()

    if my_node == node,
      do: %{init: true, scope: :local, node: my_node},
      else: %{init: false, scope: :no_label, node: :no_node}
  end

  @doc false
  def persistence_mode(node) when is_binary(node) do
    persistence_mode(String.to_atom(node))
  end

  @doc false
  def persistence_mode(_) do
    %{init: false, scope: :no_label, node: :no_node}
  end
  
  @doc false
  def raw_configuration() do
    Process.get(:history_config, [])
  end
  
  @doc false
  def inject_command(command, name \\ nil) do
     Bindings.inject_command(command, name)
  end
  
  defp handle_iex_break(expr) do
    if String.contains?(expr, "#iex:break") do
      set_prompts(:normal)
      raise("break")
    end 
  end
    
  defp send_for_parsing(expr, {bin, _}) do
    Server.iex_parse(bin  <> expr)  
  end
  
  defp send_for_parsing(expr, bin) do
    Server.iex_parse(bin  <> expr)  
  end
    
  defp query_search(fun) do
    try do
      fun.()
    catch
      _, _ -> {:error, :not_found}
    end
  end
  
  defp is_enabled!() do
    if not is_enabled?(),
      do: raise(%ArgumentError{message: "IExHistory2 is not enabled"})
  end

  defp do_load_config(filename) when is_binary(filename) do
    {:ok, [config]} = :file.consult(filename)
    config
  end
  
  defp do_load_config(app) when is_atom(app) do
    Application.get_env(app, __MODULE__, [])
  end
  
  defp do_load_config(config), do: config

  defp init_save_config(config) do
    infinity_limit = Events.infinity_limit()
    colors = Keyword.get(config, :colors, @default_colors)
    new_colors = Enum.map(@default_colors, fn {key, default} -> {key, Keyword.get(colors, key, default)} end)
    custom_regex = Keyword.get(config, :paste_eval_regex, [])
    new_keys = 
      if Keyword.get(config, :standard_arrow_keys, false) do
        Keyword.get(config, :navigation_keys, @default_navigation_keys)
        |> Keyword.merge(@standard_arrow_keys)
      else
        Keyword.get(config, :navigation_keys, @default_navigation_keys)        
      end  
    config = Keyword.delete(config, :colors)

    new_config =
      Enum.map(
        @default_config,
        fn
          {:colors, _} -> {:colors, Keyword.get(config, :colors, new_colors)}
          {:limit, current} when current > infinity_limit -> {:limit, Keyword.get(config, :limit, infinity_limit)}
          {:paste_eval_regex, regex} -> compile_regex(regex ++ custom_regex)
          {:navigation_keys, keys} -> {:navigation_keys, make_navigation_keys(keys, new_keys)}
          {key, default} -> {key, Keyword.get(config, key, default)}
        end
      ) |> List.flatten()
        
    new_config = if Keyword.get(config, :show_unmapped_keys, false),
        do: Keyword.put(new_config, :show_unmapped_keys, true),
        else: new_config  
    Process.put(:history_config, new_config)
    new_config
  end
  
  defp make_navigation_keys(keys, new_keys) do
    Keyword.merge(keys, new_keys)
    |> Enum.map(fn {k, v} when is_integer(v) -> {k, <<v>>}; x -> x end)
  end

  defp compile_regex(regex) do
    match = Enum.uniq(regex) |> Enum.map(&Regex.compile!("#{&1}<(.*)>")) 
    no_match = Enum.uniq(regex) |> Enum.map(&Regex.compile!("\"#{&1}<(.*)>\""))   
    [{:compiled_paste_eval_regex, %{match: match, no_match: no_match}}, {:paste_eval_regex, regex}]
  end
  
  defp history_configured?(config) do
    scope = Keyword.get(config, :scope, :local)

    if Events.does_current_scope_match?(scope) do
      my_node = my_real_node()

      if my_node == scope || scope in [:global, :local],
        do: true,
        else: false
    else
      false
    end
  end

  defp present_welcome(:not_ok), do: :ok

  defp present_welcome(config) do 
    inject_command("IExHistory2.state(); IEx.configure(colors: [syntax_colors: [atom: :cyan]])")
    config
  end
  
  defp set_enabled(config) do
    Process.put(:history_is_enabled, true)
    config
  end
  
  defp finalize_startup(config) do
    Process.put(:alive_prompt, IEx.Config.alive_prompt)
    Process.put(:default_prompt, IEx.Config.default_prompt)
    IEx.configure(parser: {__MODULE__, :iex_parse, []})
    Server.enable()
    if Keyword.get(config, :running_mode) == :supervisor,
      do: config,
      else: :ok
  end
    
  defp set_prompts(:paste) do
    Process.put(:iex_paste_mode, true)
    IEx.configure(alive_prompt: "  ")
    IEx.configure(default_prompt: "  ")
  end
  
  defp set_prompts(:incomplete) do
    IEx.configure(alive_prompt: "incomplete>>")
    IEx.configure(default_prompt: "incomplete>>")
  end
  
  defp set_prompts(_) do
    if Process.get(:iex_paste_mode, false) do
      IEx.configure(alive_prompt: Process.get(:alive_prompt, @alive_prompt))
      IEx.configure(default_prompt: Process.get(:default_prompt, @default_prompt))
      Process.delete(:iex_paste_mode)
    end
  end
  
end

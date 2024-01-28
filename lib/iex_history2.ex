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

  * Saves shell history between sessions.
  * Saves the shell variable bindings between VM restarts.
  * Ability to paste (most) terms into the shell.
  * Navigation keys allow history traversal where multi-line pastes require a single key up/down.
  * Shortcut functions permit search, pasting, re-evaluation and editing of items in history.
  * Editing can be done in-situ or in a text editor.
  * Shell variable bindings can be set/get outside of scope of the shell to assist in code debugging.
  * Can be enabled and state shared globally, or on individual shell sessions.

  `IExHistory2` can be enabled in `~/.iex.exs` for example:

      Code.append_path("~/github/iex_history2/_build/dev/lib/iex_history2/ebin")
      IExHistory2.initialize()

  Alternatively the project can be added as a `Mix` dependancy.

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
      
      iex> hi()                     - summary

  **NOTE:** To use `he/1` the environment variable `EDITOR` must be set to point to your editor:
  
      export EDITOR="vim"

  ## Special Functions

      iex> IExHistory2.add_binding(var, val)
      
      iex> IExHistory2.get_binding(var)
      
      iex> IExHistory2.clear_history()
      
      iex> IExHistory2.clear_bindings()
          
  The functions `IExHistory2.add_binding/2` and `IExHistory2.get_binding/1` allows variables
  to be set in a module that is invoked in the shell to be accessible in the shell and vice versa.
      
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

   
  ## Navigation
          
  The application uses a different set of keys for navigation, and attempts to present multi-line 
  terms and other items as a single line:
  
      ctrl^u    - move up through history.
      
      ctrl^k    - move down through history.
      
      ctrl^y    - allows the currently displayed item to be modified.
      
      ctrl^e    - opens the currently displayed item in an editor.
              
      ctrl^[    - reset navigation, returns to the prompt.
              
  **NOTE:** To use `ctrl^e` the environment variable `EDITOR` must be set to your editor:

  ## Configuration
    
  The following options can be set:

      [
        scope: :local,
        history_limit: :infinity,
        paste_eval_regex: [],
        import: true,
        hide_history_commands: true,
        prepend_identifiers: true,
        command_display_width: int,
        save_invalid_results: false,
        key_buffer_history: true,
        paste_eval_regex: [],
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

  To import short-cut functions set `import:` to true.
  
      import: true
      
  One current issue with the current shell is the inconsistent ability to paste large terms into
  the shell. Terms such as process ids and references (`#PID<0.1234.0>`) cause the evaluator to fail. 
  The application will attempt to recognize such terms during evaluation, wrap them in quotes and attempt
  to re-evaluate. 
  
  Currently process ids, references, anonymous functions, ports and `#Ecto.Schema.Metadata` are 
  supported by default. Additional terms can be added:
  
      paste_eval_regex: ["#SpecialItem1", "#NewObject"]
          
  This toggle true/false for calls to `IExHistory2.*` (and imports) from been saved.
        
      hide_history_commands: true 
      
  If set to false, the default, commands that were evaluated incorrectly will not be saved.
  
      save_invalid_results: false 

  If set to true will allow the user to scroll up (ctrl+u) or down (ctrl+k) through history.
      
      key_buffer_history: true
      
  Unlike the standard up/down arrow history this is command based not line based. So pasting of a large term or source code will only require 1 up or down key.
    
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

  * `:local` (the default) history will be active on all shells, even those that are remotely connected, but the history for each shell will be unique

  * `node_name`i.e. (e.g. `:mgr@localhost`) history will only be active on that shell

  * `:global` history will be shared between all shells. However the saving of variable bindings will be disabled along with the date/time in history

  If a `scope` of `:global` is selected following kernel option must be set, either directly as VM options or via an environment variable:

      export ERL_AFLAGS="-kernel shell_history enabled"

      --erl "-kernel shell_history enabled"

  ## Initialization
  
  To initialize 
  """

  @version "5.0"
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
  
  @default_width 150
  @default_colors [index: :red, date: :green, command: :yellow, label: :red, variable: :green, binding: :cyan]
  @default_config [
    scope: :local,
    history_limit: :infinity,
    hide_history_commands: true,
    prepend_identifiers: true,
    show_date: true,
    save_bindings: true,
    command_display_width: @default_width,
    paste_eval_regex: @default_paste_eval_regex,
    import: true,
    save_invalid_results: false,
    key_buffer_history: true,
    colors: @default_colors
  ]

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
  def initialize(config_or_filename \\ []) do
    config = do_load_config(config_or_filename)

    if history_configured?(config) && not is_enabled?() do
      :dbg.stop()
      new_config = init_save_config(config)
      inject_command("IEx.configure(colors: [syntax_colors: [atom: :black]])")

      if Keyword.get(new_config, :import),
        do: inject_command("import IExHistory2, only: #{inspect(@shell_imports)}")

      IExHistory2.Events.initialize(new_config)
      |> IExHistory2.Bindings.initialize()
      |> set_enabled()
      |> present_welcome()
    else
      if is_enabled?(), do: :history_already_enabled, else: :history_disabled
    end
  end

  @doc """
  Displays the current configuration.
  """
  def configuration(), do: Process.get(:history_config, [])

  @doc """
  Displays the default configuration.
  """
  def default_config(), do: @default_config

  @doc """
  Displays the current state:

      IExHistory2 version 2.0 is enabled:
        Current history is 199 commands in size.
        Current bindings are 153 variables in size.
  """
  def state() do
    IO.puts("IExHistory2 version #{IO.ANSI.red()}#{@version}#{IO.ANSI.white()} is enabled:")
    IO.puts("  #{IExHistory2.Events.state()}.")
    IO.puts("  #{IExHistory2.Bindings.state()}.")
  end

  @doc """
  Displays the entire history.
  """
  def hl() do
    is_enabled!()

    query_search(fn ->  IExHistory2.Events.get_history() end)
  end

  @doc """
  Displays the entire history from the most recent entry back (negative number),
  or from the oldest entry forward (positive number)
  """
  @spec hl(integer()) :: nil
  def hl(val) when val < 0 do
    is_enabled!()

    query_search(fn ->  IExHistory2.Events.get_history_item(val) end)
  end

  def hl(val) when val > 0 do
    is_enabled!()

    query_search(fn ->  IExHistory2.Events.get_history_items(1, val) end)
  end

  @doc """
  Specify a range, the atoms :start and :stop can also be used.
  """
  @spec hl(integer(), integer()) :: nil
  def hl(start, stop) do
    is_enabled!()

    query_search(fn ->  IExHistory2.Events.get_history_items(start, stop) end)
  end

  @doc """
  Returns the list of expressions where all or part of the string matches.

  The original expression does not need to be a string.
  """
  @spec hs(String.t()) :: nil
  def hs(match) do
    is_enabled!()

    query_search(fn ->  IExHistory2.Events.search_history_items(match, :exact) end)
  end

  @doc """
  A case insensitive search the list of expressions where all or part of the string matches.

  The original expression does not need to be a string.
  """
  @spec hsi(String.t()) :: nil
  def hsi(match) do
    is_enabled!()

    query_search(fn ->  IExHistory2.Events.search_history_items(match, :ignore_case) end)
  end
  
  @doc """
  Like `hsa/1` a case insensitive search, but also adds a closeness element to the search.

  It uses a combination of Myers Difference and Jaro Distance to get close to a match. The
  estimated closeness is indicated in the result with a default range of > 80%.
  This can be set by the user.
  
  For large histories this command may take several seconds.
  
  The original expression does not need to be a string.
  """
  @spec hsa(String.t(), integer()) :: nil
  def hsa(match, closeness \\ 80) do
    is_enabled!()

    query_search(fn ->  IExHistory2.Events.search_history_items(match, :approximate, closeness) end)
  end
  
  @doc """
  Invokes the command at index 'i'.
  """
  @spec hx(integer()) :: any()
  def hx(i) do
    is_enabled!()

    try do
      IExHistory2.Events.execute_history_item(i)
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
    
    query_search(fn -> IExHistory2.Events.copy_paste_history_item(i) end)
  end

  @spec he(integer()) :: any()
  def he(i) do
    is_enabled!()

     query_search(fn ->  IExHistory2.Events.edit_history_item(i) end)
  end

  @doc """
  Show the variable bindings.
  """
  def hb(),
    do: IExHistory2.Bindings.display_bindings()

  @doc """
  Show history information summary.
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
    IExHistory2.Events.clear()
    IExHistory2.Bindings.clear()

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
    IExHistory2.Events.clear_history(val)

    if IExHistory2.configuration(:scope, :local) == :global && val == :all,
      do: IO.puts("\n#{IO.ANSI.green()}Please restart your shell session for the changes to take effect")

    :ok
  end

  @doc """
  Clears the bindings.
  """
  def clear_bindings() do
    IExHistory2.Bindings.clear()
    :ok
  end

  @doc """
  Clears the history and bindings then stops the service. If `scope` is ` :global` the IEx session needs restarting for the changes to take effect.
  """
  def stop_clear() do
    IExHistory2.Events.stop_clear()
    IExHistory2.Bindings.stop_clear()

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
  Returns the current shell bindings.
  """
  def get_bindings() do
    IExHistory2.Bindings.get_bindings()
  end

  @doc """
  This helper function can be used when testing code (for example a module pasted into the shell).
  It allows a variable that is set in the shell to be available in a module under test. For example:
  
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
      IExHistory2.Bindings.get_binding(var)
    rescue
    _ -> raise("undefined variable #{var}")  
    end
  end
  
  @doc """
  Experimental. Same as `get_binding/2`, but `name` is the registered name of a shell pid.
  
  See `register/1`
  """
  @spec get_binding(atom() | String.t(), atom()) :: any()  
  def get_binding(var, name) when is_bitstring(var) do
    get_binding(String.to_atom(var), name)
  end
  
  def get_binding(var, name) do
    try do
      IExHistory2.Bindings.get_binding(var, name)
    rescue
    _ -> raise("undefined variable #{var}")  
    end
  end
  
  @doc """
  This helper function can be used when testing code (for example a module pasted into the shell).
  It allows a variable to be set that will become available in the shell. For example:
  
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
  Experimental. Same as `add_binding/2`, but `name` is the registered name of a shell pid.
  
  See `register/1`
  """
  @spec add_binding(atom() | String.t(), any(), atom()) :: :ok
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
  def unbind(vars) when is_list(vars), do: IExHistory2.Bindings.unbind(vars)
  def unbind(var), do: unbind([var])

  @doc """
  Saves the current configuration to file.
  """
  def save_config(filename) do
    data = :io_lib.format("~p.", [configuration()]) |> List.flatten()
    :file.write_file(filename, data)
  end

  @doc """
  Loads the current configuration to file `IExHistory2.save_config()`.

  NOTE: Not all options can be set during run-time. Instead pass the filename as a single argument to `IExHistory2.initialize()`
  """
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
      :save_bindings,
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
    IExHistory2.Events.send_message({:hide_history_commands, value})
    Process.put(:history_config, new_config)
    configuration()
  end

  def configure(:key_buffer_history, value) when value in [true, false] do
    new_config = List.keyreplace(configuration(), :key_buffer_history, 0, {:key_buffer_history, value})
    IExHistory2.Events.send_message({:key_buffer_history, value})
    Process.put(:history_config, new_config)
    configuration()
  end

  def configure(:save_invalid_results, value) when value in [true, false] do
    new_config = List.keyreplace(configuration(), :save_invalid_results, 0, {:save_invalid_results, value})
    IExHistory2.Events.send_message({:save_invalid_results, value})
    Process.put(:history_config, new_config)
    configuration()
  end

  def configure(:prepend_identifiers, value) when value in [true, false] do
    new_config = List.keyreplace(configuration(), :prepend_identifiers, 0, {:prepend_identifiers, value})
    IExHistory2.Events.send_message({:prepend_identifiers, value})
    Process.put(:history_config, new_config)
    configuration()
  end

  def configure(:history_limit, value) when is_integer(value) or value == :infinity do
    new_config = List.keyreplace(configuration(), :history_limit, 0, {:history_limit, value})
    new_value = if value == :infinity, do: IExHistory2.Events.infinity_limit(), else: value
    IExHistory2.Events.send_message({:new_history_limit, new_value})
    Process.put(:history_config, new_config)
    configuration()
  end

  def configure(:save_bindings, value) when value in [true, false] do
    if configuration(:scope, :local) != :global do
      current_value = configuration(:save_bindings, true)
      new_config = List.keyreplace(configuration(), :save_bindings, 0, {:save_bindings, value})

      if current_value == true,
        do: IExHistory2.Bindings.stop_clear(),
        else: IExHistory2.Bindings.initialize(new_config)

      Process.put(:history_config, new_config)
      configuration()
    else
      {:error, :scope_is_global}
    end
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
  def my_real_node(), do: :erlang.node(Process.group_leader())

  @doc false
  def module_name(), do: @module_name

  @doc false
  def exec_name(), do: @exec_name

  @doc false
  def exclude_from_history() do
    @exclude_from_history_methods
  end

  @doc false
  def configuration(item, default), do: Keyword.get(configuration(), item, default)

  @doc false
  def persistence_mode(:local) do
    my_node = my_real_node()
    {:ok, true, :local, my_node}
  end

  @doc false
  def persistence_mode(:global), do: {:ok, true, :global, :no_node}

  @doc false
  def persistence_mode(node) when is_atom(node) do
    my_node = my_real_node()

    if my_node == node,
      do: {:ok, true, :local, my_node},
      else: {:ok, false, :no_label, :no_node}
  end

  @doc false
  def persistence_mode(node) when is_binary(node) do
    persistence_mode(String.to_atom(node))
  end

  @doc false
  def persistence_mode(_), do: {:ok, false, :no_label, :no_node}

  @doc false
  def inject_command(command, name \\ nil), do: IExHistory2.Bindings.inject_command(command, name)

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

  defp do_load_config(config), do: config

  defp init_save_config(config) do
    infinity_limit = IExHistory2.Events.infinity_limit()
    colors = Keyword.get(config, :colors, @default_colors)
    new_colors = Enum.map(@default_colors, fn {key, default} -> {key, Keyword.get(colors, key, default)} end)
    custom_regex = Keyword.get(config, :paste_eval_regex, [])
    config = Keyword.delete(config, :colors)

    new_config =
      Enum.map(
        @default_config,
        fn
          {:colors, _} -> {:colors, Keyword.get(config, :colors, new_colors)}
          {:limit, current} when current > infinity_limit -> {:limit, Keyword.get(config, :limit, infinity_limit)}
          {:paste_eval_regex, regex} -> compile_regex(regex ++ custom_regex)
          {key, default} -> {key, Keyword.get(config, key, default)}
        end
      ) |> List.flatten()
            
    if Keyword.get(new_config, :scope, :local) == :global do
      newer_config = List.keyreplace(new_config, :save_bindings, 0, {:save_bindings, false})
      Process.put(:history_config, newer_config)
      newer_config
    else
      Process.put(:history_config, new_config)
      new_config
    end
  end

  defp compile_regex(regex) do
    compiled = Enum.uniq(regex) |> Enum.map(&Regex.compile!("#{&1}<(.*)>"))  
    [{:compiled_paste_eval_regex, compiled}, {:paste_eval_regex, regex}]
  end
  
  defp history_configured?(config) do
    scope = Keyword.get(config, :scope, :local)

    if IExHistory2.Events.does_current_scope_match?(scope) do
      my_node = my_real_node()

      if my_node == scope || scope in [:global, :local],
        do: true,
        else: false
    else
      false
    end
  end

  defp present_welcome(:not_ok), do: :ok

  defp present_welcome(_), do: inject_command("IExHistory2.state(); IEx.configure(colors: [syntax_colors: [atom: :cyan]])")

  defp set_enabled(config) do
    Process.put(:history_is_enabled, true)
    config
  end
end

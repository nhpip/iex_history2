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

defmodule History do
  @moduledoc """
  Saves shell history and variable bindings between shell sessions.

  Allows the user to display history, and re-issue historic commands, made much easier since the variable bindings are saved.

  History can be enabled in `~/.iex.exs` for example:

      Code.append_path("~/github/history/_build/dev/lib/iex_history/ebin")
      History.initialize(history_limit: 200, scope: :local, show_date: true, colors: [index: :red])

  The application can, of course, be added as a dependency to mix.exs

  ## Functions
    
      iex> hl()             - Will list the entire history.
      
      iex> hl(val)          - Will list `val` entries from the start if val is positive, or from the end if negative.
      
      iex> hl(start, stop)  - Will list entries between `start` and `stop`.
      
      iex> hs(string)       -  Will list entries that match all or part the query string.
      
      iex> hx(pos)          - Will execute the expression at position `pos`.
      
      iex> hc(pos)          - Will copy the expression at position pos to the shell.
      
      iex> he(pos)          - Edit the expression in a text editor.
      
      iex> hb()             - Displays the current bindings.
      
      iex> hi()             - Summary
  
  NOTE: To use `he/1` the environment variable `VISUAL` must be set to point to the editor
  
  ## Admin Functions
  
      iex> History.add_binding(var, val)
      
      iex> History.get_binding(var)
      
      iex> History.clear_history()
      
      iex> History.clear_bindings()
          
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
        import: true,
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


    `:import` Will import history query functions to the shell.
        
    `:hide_history_commands ` This will prevent all calls to `History.*` from been saved.

    NOTE: `History.x/1` is always hidden. Scope of `:global` will only hide them from output, otherwise they will not be saved.

    `:save_invalid_results ` If set to false, the default, commands that were evaluated incorrectly will not be saved.

    `:key_buffer_history ` If set to true will allow the user to scroll up (ctrl+u) or down (ctrl+k) through history.
    Unlike the standard up/down arrow history this is command based not line based. So pasting of a large structure will only require 1 up or down.
    This mechanism also saves commands that were not properly evaluated; however there is a buffer limit of 75 lines, although this can be changed by updating
    `@history_buffer_size` in `events_server.ex`. This will also not duplicate back to back identical commands.

    `:prepend_identifiers ` If this is enabled it will prepend identifiers when a call to `x = hx(val)` is issued.

    For example:

      enabled:
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

        disabled:
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


    `scope` can be one of `:local, :global `or a `node name`

    If `scope` is `:local` (the default) history will be active on all shells, even those that are remotely connected, but the history for each shell will be unique

    If `scope` is `node()` (e.g. `:mgr@localhost`) history will only be active on that shell

    If `scope` is `:global` history will be shared between all shells. However the saving of variable bindings will be disabled along with the date/time in history

    Furthermore, if a `scope` of `:global` is selected following kernel option must be set, either directly as VM options or via an environment variable:

      export ERL_AFLAGS="-kernel shell_history enabled"

      --erl "-kernel shell_history enabled"

  """

  @version "5.0"
  @module_name String.trim_leading(Atom.to_string(__MODULE__), "Elixir.")
  @exec_name String.trim_leading(Atom.to_string(__MODULE__) <> ".x", "Elixir.")

  @excluded_history_functions [".h(", ".x(", ".c("]
  @excluded_history_imports   ["hc(", "hl(", "hs(", "hx(", "hb(", "hi("]
  @exclude_from_history for f <- @excluded_history_functions, do: @module_name <> f

  @default_width 150
  @default_colors [index: :red, date: :green, command: :yellow, label: :red, variable: :green]
  @default_config [scope: :local, history_limit: :infinity, hide_history_commands: true, prepend_identifiers: true,
                   show_date: true, save_bindings: true, command_display_width: @default_width, import: true,
                   save_invalid_results: false, key_buffer_history: true, colors: @default_colors]

  @doc """
    Initializes the History app. Takes the following parameters:

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
        save_bindings: true,
        colors: [
          index: :red,
          date: :green,
          command: :yellow,
          label: :red,
          variable: :green
        ]
      ]

    Alternatively a filename can be given that was saved with `History.save_config()`

    `scope` can be one of `:local, :global` or a `node()` name
  """
  def initialize(config_or_filename \\ []) do
    config = do_load_config(config_or_filename)
    if history_configured?(config) && not is_enabled?() do
      :dbg.stop()
      new_config = init_save_config(config) 
      inject_command("IEx.configure(colors: [syntax_colors: [atom: :black]])")
      if Keyword.get(new_config, :import),
        do: inject_command("import History, only: [hl: 0, hl: 1, hl: 2, hs: 1, hc: 1, hx: 1, hb: 0, hi: 0, he: 1]")
      History.Events.initialize(new_config)
      |> History.Bindings.initialize()
      |> set_enabled()
      |> present_welcome()
      else
      if is_enabled?(), do: :history_already_enabled, else: :history_disabled
    end
  end

  @doc """
    If you want to setup an alias like `alias History, as: H` rather than using `alias/2`
    from the shell, please use this function instead. So to create an alias of `H` use `History.alias(H)`.
    This allows aliased functions to be handled correctly.
  """
  def alias(name) when is_atom(name) do
    if Process.get(:history_alias) == nil do
      string_name = Atom.to_string(name) |> String.replace("Elixir.", "")
      inject_command_all_servers("alias(#{__MODULE__}, as: #{string_name})")
      excluded = for fun <- @excluded_history_functions, do: string_name <> fun
      base_name = string_name <> "."
      Process.put(:history_alias, base_name)
      History.Events.send_message({:module_alias, base_name})
      ## TODO: Find a better way
      :persistent_term.put(:history_aliases, excluded ++ :persistent_term.get(:history_aliases, []))
    end
  end

  @doc """
    Displays the current configuration.
  """
  def configuration(), do:
    Process.get(:history_config, [])

  @doc """
    Displays the default configuration.
  """
  def default_config(), do: @default_config

  @doc """
    Displays the current state:

      History version 2.0 is enabled:
        Current history is 199 commands in size.
        Current bindings are 153 variables in size.
  """
  def state() do
    IO.puts("History version #{IO.ANSI.red()}#{@version}#{IO.ANSI.white()} is enabled:")
    IO.puts("  #{History.Events.state()}.")
    IO.puts("  #{History.Bindings.state()}.")
  end
   
  @doc """
    Displays the entire history.
  """
  def hl() do
    is_enabled!()
    try do
      History.Events.get_history()
    catch
      _, _ -> {:error, :not_found}
    end
  end

  @doc """
  Displays the entire history from the most recent entry back (negative number),
  or from the oldest entry forward (positive number)
  """
  @spec hl(integer()) :: nil 
  def hl(val) when val < 0 do
    is_enabled!()
    try do
      History.Events.get_history_item(val)
      :ok
    catch
      _, _ -> {:error, :not_found}
    end
  end
    
  def hl(val) when val > 0 do
    is_enabled!()
    try do
      History.Events.get_history_items(1, val)
      :ok
    catch
      _, _ -> {:error, :not_found}
    end
end

  @doc """
  Specify a range, the atoms :start and :stop can also be used.
  """
  @spec hl(integer(), integer()) :: nil 
  def hl(start, stop) do
    is_enabled!()
    try do
      History.Events.get_history_items(start, stop)
      :ok
    catch
      _, _ -> {:error, :not_found}
    end
  end
      
  @doc """
  Returns the list of expressions where all or part of the string matches.
  
  The original expression does not need to be a string.
  """
  @spec hs(String.t()) :: nil
  def hs(match) do
    is_enabled!()
    try do
      History.Events.get_history_item(match)
      :ok
    catch
      _, _ -> {:error, :not_found}
    end
  end
  
  @doc """
  Invokes the command at index 'i'.
  """
  @spec hx(integer()) :: any() 
  def hx(i) do
    is_enabled!()
    try do
      History.Events.execute_history_item(i)
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
    try do
      History.Events.copy_paste_history_item(i)
    catch
      _, _ -> {:error, :not_found}
    end
  end
  
  @spec he(integer()) :: any() 
  def he(i) do
    is_enabled!()
    try do
      History.Events.edit_history_item(i)
    catch
      _, _ -> {:error, :not_found}
    end
  end
  
  @doc """
  Show the variable bindings.
  """
  def hb(),
    do: get_bindings()
  
  @doc """
  Show history information summary.
  """
  def hi(),
    do: state()
  
  ###
  # Backwards compatibility
  ###
  def h(), do: hl()
  def h(val), do: hl(val)
  def h(start, stop), do: hl(start, stop)
  def c(val), do: hc(val)
  def x(val), do: hx(val)
  
  @doc """
    Clears the history and bindings. If `scope` is `:global`
    the IEx session needs restarting for the changes to take effect.
  """
  def clear() do
    History.Events.clear()
    History.Bindings.clear()
    if History.configuration(:scope, :local) == :global, do:
      IO.puts("\n#{IO.ANSI.green()}Please restart your shell session for the changes to take effect")
    :ok
  end

  @doc """
    Clears the history only. If `scope` is `:global`
    the IEx session needs restarting for the changes to take effect. If a value is passed it will clear that many history
    entries from start, otherwise the entire history is cleared.
  """
  def clear_history(val \\ :all) do
    History.Events.clear_history(val)
    if History.configuration(:scope, :local) == :global && val == :all, do:
      IO.puts("\n#{IO.ANSI.green()}Please restart your shell session for the changes to take effect")
    :ok
  end

  @doc """
    Clears the bindings.
  """
  def clear_bindings() do
    History.Bindings.clear()
    :ok
  end

  @doc """
      Clears the history and bindings then stops the service. If `scope` is ` :global` the IEx session needs restarting for the changes to take effect.
  """
  def stop_clear() do
    History.Events.stop_clear()
    History.Bindings.stop_clear()
    if History.configuration(:scope, :local) == :global, do:
      IO.puts("\n#{IO.ANSI.green()}Please restart your shell session for the changes to take effect")
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
    History.Bindings.get_bindings()
  end
  
  def get_binding(var) when is_bitstring(var) do
    History.Bindings.get_binding(String.to_atom(var))
  end
  
  def get_binding(var) do
    History.Bindings.get_binding(var)
  end
  
  @doc """
    Unbinds a variable or list of variables (specify variables as atoms, e.g. foo becomes :foo).
  """
  def unbind(vars) when is_list(vars), do:
    History.Bindings.unbind(vars)
  def unbind(var), do:
    unbind([var])

  @doc """
    Saves the current configuration to file.
  """
  def save_config(filename) do
    data = :io_lib.format("~p.", [configuration()]) |> List.flatten()
    :file.write_file(filename, data)
  end

  @doc """
    Loads the current configuration to file `History.save_config()`.

    NOTE: Not all options can be set during run-time. Instead pass the filename as a single argument to `History.initialize()`
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
      History.configure(:colors, [index: :blue])
      History.configure(:prepend_identifiers, true)
  """
  @spec configure(Atom.t(), any) :: atom
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
    History.Events.send_message({:hide_history_commands, value})
    Process.put(:history_config, new_config)
    configuration()
  end

  def configure(:key_buffer_history, value) when value in [true, false] do
    new_config = List.keyreplace(configuration(), :key_buffer_history, 0, {:key_buffer_history, value})
    History.Events.send_message({:key_buffer_history, value})
    Process.put(:history_config, new_config)
    configuration()
  end

  def configure(:save_invalid_results, value) when value in [true, false] do
    new_config = List.keyreplace(configuration(), :save_invalid_results, 0, {:save_invalid_results, value})
    History.Events.send_message({:save_invalid_results, value})
    Process.put(:history_config, new_config)
    configuration()
  end

  def configure(:prepend_identifiers, value) when value in [true, false] do
    new_config = List.keyreplace(configuration(), :prepend_identifiers, 0, {:prepend_identifiers, value})
    History.Events.send_message({:prepend_identifiers, value})
    Process.put(:history_config, new_config)
    configuration()
  end

  def configure(:history_limit, value) when is_integer(value) or value == :infinity do
    new_config = List.keyreplace(configuration(), :history_limit, 0, {:history_limit, value})
    new_value = if value == :infinity, do: History.Events.infinity_limit(), else: value
    History.Events.send_message({:new_history_limit, new_value})
    Process.put(:history_config, new_config)
    configuration()
  end

  def configure(:save_bindings, value) when value in [true, false] do
    if configuration(:scope, :local) != :global do
      current_value = configuration(:save_bindings, true)
      new_config = List.keyreplace(configuration(), :save_bindings, 0, {:save_bindings, value})
      if current_value == true,
          do: History.Bindings.stop_clear(),
          else: History.Bindings.initialize(new_config)
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
  def get_color_code(for), do:
    Kernel.apply(IO.ANSI, configuration(:colors, @default_colors)[for], [])

  @doc false
  def get_log_path() do
    filename = :filename.basedir(:user_cache, 'erlang-history') |> to_string()
    File.mkdir_p!(filename)
    filename
  end

  def save_binding(var, value) do
    inject_command("#{var} = #{inspect(value, limit: :infinity, printable_limit: :infinity)}") 
    :ok 
  end
  
  def save_binding(value) do
    inject_command("#{inspect(value, limit: :infinity, printable_limit: :infinity)}") 
    :ok 
  end
  
  @doc false
  def my_real_node(), do:
    :erlang.node(Process.group_leader())

  @doc false
  def module_name(), do: @module_name

  @doc false
  def exec_name(), do: @exec_name

  @doc false
  def exclude_from_history() do
    aliases = :persistent_term.get(:history_aliases, [])
    @exclude_from_history ++ @excluded_history_imports ++ aliases ++ ["\n{:success, :history"]
  end

  @doc false
  def configuration(item, default), do:
    Keyword.get(configuration(), item, default)

  @doc false
  def persistence_mode(:local) do
    my_node = my_real_node()
    {:ok, true, :local, my_node}
  end

  @doc false
  def persistence_mode(:global), do:
    {:ok, true, :global, :no_node}

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
  def persistence_mode(_), do:
    {:ok, false, :no_label, :no_node}

  @doc false
  def inject_command(command), do:
    History.Bindings.inject_command(command)

  defp inject_command_all_servers(command) do
    Enum.each(Process.list(),
                  fn(pid) ->
                      server = :group.whereis_shell()
                      if not is_nil(server),
                         do: send(pid, {:eval, server, command, 1, {"", :other}})
                  end)
  end

  defp is_enabled!() do
    if not is_enabled?(),
       do: raise(%ArgumentError{message: "History is not enabled"})
  end

  defp do_load_config(filename) when is_binary(filename) do
    {:ok, [config]} = :file.consult(filename)
    config
  end

  defp do_load_config(config), do:
    config

  defp init_save_config(config) do
    infinity_limit = History.Events.infinity_limit()
    colors = Keyword.get(config, :colors, @default_colors)
    new_colors = Enum.map(@default_colors, fn({key, default}) -> {key, Keyword.get(colors, key, default)} end)
    config = Keyword.delete(config, :colors)
    new_config = Enum.map(@default_config,
                      fn({:colors, _}) -> {:colors, Keyword.get(config, :colors, new_colors)}
                        ({:limit, current}) when current > infinity_limit ->   {:limit, Keyword.get(config, :limit, infinity_limit)}
                        ({key, default}) -> {key, Keyword.get(config, key, default)}
                      end)
    if Keyword.get(new_config, :scope, :local) == :global  do
      newer_config = List.keyreplace(new_config, :save_bindings, 0, {:save_bindings, false})
      Process.put(:history_config, newer_config)
      newer_config
    else
      Process.put(:history_config, new_config)
      new_config
    end
  end

  defp history_configured?(config) do
    scope = Keyword.get(config, :scope, :local)
    if History.Events.does_current_scope_match?(scope) do
      my_node = my_real_node()
      if my_node == scope || scope in [:global, :local],
        do: true,
        else: false
    else
      false
    end
  end

  defp present_welcome(:not_ok), do:
    :ok

  defp present_welcome(_), do:
    inject_command("History.state(); IEx.configure(colors: [syntax_colors: [atom: :cyan]])")

  defp set_enabled(config) do
    Process.put(:history_is_enabled, true)
    config
  end

end

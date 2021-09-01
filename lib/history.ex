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
    Saves shell history and optionally variable bindings between shell sessions.

    Allows the user to display history, and re-issue historic commands, made much easier since the
    variable bindings are saved.

    For ease History can be enabled in #{IO.ANSI.cyan()}~/.iex.exs#{IO.ANSI.white()} for example:

      Code.append_path("~/github/history/_build/dev/lib/history/ebin")
      History.initialize(history_limit: 200, scope: :local, show_date: true, colors: [index: :red])

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

    #{IO.ANSI.cyan()}scope#{IO.ANSI.white()} can be one of #{IO.ANSI.cyan()}:local, :global #{IO.ANSI.white()}or a #{IO.ANSI.cyan()}node name#{IO.ANSI.white()}

    If #{IO.ANSI.cyan()}scope#{IO.ANSI.white()} is #{IO.ANSI.cyan()}:local#{IO.ANSI.white()} (the default) history will be active on all shells, even those that are remotely connected, but the history for each shell will be unique

    If #{IO.ANSI.cyan()}scope#{IO.ANSI.white()} is #{IO.ANSI.cyan()}node()#{IO.ANSI.white()} (e.g. #{IO.ANSI.cyan()}:mgr@localhost#{IO.ANSI.white()}) history will only be active on that shell

    If #{IO.ANSI.cyan()}scope#{IO.ANSI.white()} is #{IO.ANSI.cyan()}:global#{IO.ANSI.white()} history will be shared between all shells. However the saving of variable bindings will be disabled along with the date/time in history

    Furthermore, if a #{IO.ANSI.cyan()}scope#{IO.ANSI.white()} of #{IO.ANSI.cyan()}:global#{IO.ANSI.white()} is selected following kernel option must be set, either directly as VM options or via an environment variable:

      export ERL_AFLAGS="-kernel shell_history enabled"

      --erl "-kernel shell_history enabled"
  """

  @version "2.0"
  @module_name String.trim_leading(Atom.to_string(__MODULE__) <> ".", "Elixir.")
  @exec_name String.trim_leading(Atom.to_string(__MODULE__) <> ".x", "Elixir.")

  @default_colors [index: :red, date: :green, command: :yellow, label: :red, variable: :green]
  @default_config [scope: :local, history_limit: :infinity, hide_history_commands: true, show_date: true, save_bindings: true, colors: @default_colors]

  @doc """
    Initializes the History app. Takes the following parameters:

      [
        scope: :local,
        history_limit: :infinity,
        hide_history_commands: true.
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

    #{IO.ANSI.cyan()}scope#{IO.ANSI.white()} can be one of #{IO.ANSI.cyan()}:local, :global#{IO.ANSI.white()} or a #{IO.ANSI.cyan()}node()#{IO.ANSI.white()} name
  """
  def initialize(config \\ []) do
    if history_configured?(config) && not is_enabled?() do
      new_config = save_config(config)
      History.Bindings.inject_command("IEx.configure(colors: [syntax_colors: [atom: :black]])")
      History.Events.initialize(new_config)
      |> History.Bindings.initialize()
      |> set_enabled()
      |> present_welcome()
    else
      if is_enabled?(), do: :history_already_enabled, else: :history_disabled
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

      History version 2.0 is eenabled:
        Current history is 199 commands in size.
        Current bindings are 153 variables in size.
  """
  def state() do
    IO.puts("#{IO.ANSI.white()}History version #{IO.ANSI.red()}#{@version}#{IO.ANSI.white()} is eenabled:")
    IO.puts("  #{History.Events.state()}.")
    IO.puts("  #{History.Bindings.state()}.")
  end

  @doc """
    Displays the entire history.
  """
  def h() do
    try do
      History.Events.get_history()
    catch
      _,_ -> {:error, :not_running}
    end
  end

  @doc """
    If the argument is a string it displays the history that contain or match entirely the passed argument.
    If the argument is an integer it displays the command at that index.
  """
  @spec h(String.t() | integer) :: atom
  def h(val)

  def h(match) do
    try do
      History.Events.get_history_item(match)
    catch
      _,_ -> {:error, :not_running}
    end
  end

  @doc """
    Invokes the command at index 'i'.
  """
  def x(i) do
    try do
      History.Events.execute_history_item(i)
    catch
      _,_ -> {:error, :not_running}
    end
  end

  @doc """
    Clears the history. If #{IO.ANSI.cyan()}scope#{IO.ANSI.white()} is #{IO.ANSI.cyan()}:global#{IO.ANSI.white()}
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
      Clears the history and stops the service. If #{IO.ANSI.cyan()}scope#{IO.ANSI.white()} is #{IO.ANSI.cyan()} :global#{IO.ANSI.white()} the IEx session needs restarting for the changes to take effect.
  """
  def stop_clear() do
    History.Events.stop_clear()
    History.Bindings.stop_clear()
    if History.configuration(:scope, :local) == :global, do:
      IO.puts("\n#{IO.ANSI.green()}Please restart your shell session for the changes to take effect")
    :ok
  end

  @doc """
    Returns #{IO.ANSI.cyan()}true#{IO.ANSI.white()} or #{IO.ANSI.cyan()}false#{IO.ANSI.white()} depending on if history is enabled.
  """
  def is_enabled?() do
    Process.get(:history_is_enabled, false)
  end

  @doc """
    Returns the current shell bindings.
  """
  def get_bindings() do
    try do
      :ets.tab2list(Process.get(:history_bindings_ets_label))
    catch
      _,_ -> []
    end
  end

  @doc """
    Allows the following options to be changed, but not saved:
      :show_date
      :history_limit
      :hide_history_commands,
      :save_bindings
  """
  @spec configure(Atom.t(), any) :: atom
  def configure(kry, val)

  def configure(:show_date, value) when value in [true, false] do
    new_config = List.keyreplace(configuration(), :show_date, 0, {:show_date, value})
    Process.put(:history_config, new_config)
    configuration()
  end

  def configure(:hide_history_commands, value) when value in [true, false] do
    new_config = List.keyreplace(configuration(), :hide_history_commands, 0, {:hide_history_commands, value})
    History.Events.send_msg({:hide_history_commands, value})
    Process.put(:history_config, new_config)
    configuration()
  end

  def configure(:history_limit, value) when is_integer(value) or value == :infinity do
    new_config = List.keyreplace(configuration(), :history_limit, 0, {:history_limit, value})
    new_value = if value == :infinity, do: History.Events.infinity_limit(), else: value
    History.Events.send_msg({:new_history_limit, new_value})
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

  @doc """
    Allows the colors to be changed, but not saved
  """
  def configure(:colors, item, value) do
    new_colors = List.keyreplace(configuration(:colors, []), item, 0, {item ,value})
    new_config = List.keyreplace(configuration(), :colors, 0, {:colors, new_colors})
    Process.put(:history_config, new_config)
    configuration()
  end

  @doc false
  def get_color_code(for), do:
    Kernel.apply(IO.ANSI, configuration(:colors, @default_colors)[for], [])

  @doc false
  def get_log_path(), do:
    :filename.basedir(:user_cache, 'erlang-history') |> to_string()

  @doc false
  def my_real_node(), do:
    :erlang.node(Process.group_leader())

  @doc false
  def module_name(), do: @module_name

  @doc false
  def exec_name(), do: @exec_name

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

  defp save_config(config) do
    infinity_limit = History.Events.infinity_limit()
    colors = Keyword.get(config, :colors, @default_colors)
    new_colors = Enum.map(@default_colors,
      fn({key, default}) -> {key, Keyword.get(colors, key, default)}
      end)
    config = Keyword.delete(config, :colors)
    new_config = Enum.map(@default_config,
      fn({key, default}) ->
        default = if key == :colors, do: new_colors, else: default
        default = if key == :limit do
                     if default > infinity_limit,
                       do: infinity_limit,
                       else: default
                     else
                       default
                     end
        {key, Keyword.get(config, key, default)}
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
    History.Bindings.inject_command("History.state(); IEx.configure(colors: [syntax_colors: [atom: :cyan]])")

  defp set_enabled(config) do
    Process.put(:history_is_enabled, true)
    config
  end

end

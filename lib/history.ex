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
    Saves history between shell sessions. Allows the user to display history, and re-issue historic commands.
  """

  @disk_log_tag :"$#group_history"
  @module_name String.trim_leading(Atom.to_string(__MODULE__) <> ".", "Elixir.")

  @doc """
    Displays the entire history.
  """
  def h() do
    get_history() |> Enum.reduce(1, fn(cmd, count) -> IO.puts("\e[31m#{count}:\e[33m #{cmd}"); count+1 end)
    :ok
  end

  @doc """
    If the argument is a string it displays the history that contain or match entirely the passed argument.
    If the argument is an integer it displays the command at that index.
  """
  @spec h(String.t | integer) :: atom
  def h(val)

  def h(match) when is_binary(match) do
    get_history()
    |> Enum.reduce(1, fn(cmd, count) ->
            if String.contains?(cmd, match) do
              IO.puts("\e[31m#{count}:\e[33m #{cmd}")
              count+1
            else
              count+1
            end
    end)
    :ok
  end

  def h(i), do:
    IO.puts("\e[33m #{get_history_item(i)}")

  @doc """
    Invokes the command at index 'i'.
  """
  def x(i) do
    cmd = get_history_item(i)
    send(self(), {:eval, Process.info(self())[:dictionary][:iex_server], cmd, %IEx.State{}})
    :rpc.call(:erlang.node(:erlang.group_leader()), :group_history, :add, [to_charlist(cmd)])
    :ok
  end

  @doc """
    Clears the history. The IEx session needs restarting for the changes to take effect.
  """
  def clear() do
    get_log_path() |> File.rm_rf!
    IO.puts "\e[33m Please restart your shell session for the changes to take effect"
  end

  defp get_history() do
    :rpc.call(:erlang.node(:erlang.group_leader()), :group_history, :load, [])
    |> Enum.map(fn cmd -> String.trim(to_string(cmd)) end)
    |> Enum.filter(fn cmd -> not String.starts_with?(cmd, @module_name) end)
    |> Enum.reverse()
  end

  defp get_history_item(i), do:
    get_history() |> Enum.at(i-1)

  defp get_log_path(), do:
    :disk_log.info(@disk_log_tag)[:file] |> to_string() |> String.trim_trailing("erlang-shell-log")

end

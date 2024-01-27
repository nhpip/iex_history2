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

defmodule IExHistory2.Events do
  @moduledoc false

  # So dets doesn't get too big, may find a better way
  @infinity_limit 3000
  @store_name "store_history_events"
  @random_string "adarwerwvwvevwwerxrwfx"

  alias IExHistory2.Events.Server

  @doc false
  def initialize(config) do
    scope = Keyword.get(config, :scope, :local)

    if scope != :global do
      set_group_history(:disabled)
      IExHistory2.persistence_mode(scope) |> do_initialize()
      config
    else
      set_group_history(:enabled)
      config
    end
  end

  @doc false
  def get_history() do
    IExHistory2.configuration(:scope, :local)
    |> do_get_history()
    |> pp_history_items(1)
  end

  @doc false
  def search_history_items(match, closeness, distance \\ 100) when is_binary(match) do
    results = IExHistory2.configuration(:scope, :local)
      |> do_get_history()
      |> Enum.map_reduce(1,
            fn {date, command}, count ->
              diff = history_item_contains?(command, match, closeness)
              if (diff * 100) >= distance,
              do: {{diff, count, date, command}, count + 1}, 
              else: {[], count + 1}
      end)
      |> elem(0)
      |> List.flatten()
    
    sorted = if closeness == :approximate,
              do: Enum.sort_by(results, &(elem(&1, 0)), :desc),
              else: Enum.sort_by(results, &(elem(&1, 1)), :asc)
              
    Enum.each(sorted, fn {diff, count, date, command} ->
          if closeness == :approximate do 
            match = "#{IO.ANSI.yellow()}#{inspect(round(diff* 100))}% "  
            display_formatted_date(count, date, command, match)
          else
            display_formatted_date(count, date, command)              
          end
    end)
  end
  
  @doc false
  def get_history_item(i) when i >= 1 do
    {date, command} = do_get_history_item(i)
    display_formatted_date(i, date, command)
  end

  @doc false
  def get_history_item(i) do
    do_get_history_item(i)
    |> pp_history_items(state(:number) + i)
  end

  @doc false
  def get_history_items(start, stop) do
    real_start = if is_atom(start), do: 1, else: start

    do_get_history_range(start, stop)
    |> pp_history_items(real_start)
  end

  @doc false
  def execute_history_item(i) do
    {_date, command} = do_get_history_item(i)
    {result, _} = Code.eval_string(command, IExHistory2.get_bindings())

    if IExHistory2.configuration(:scope, :local) == :global,
      do: :rpc.call(:erlang.node(:erlang.group_leader()), :group_history, :add, [to_charlist(command)]),
      else: Server.save_history_command(command)

    result
  end

  @doc false
  def copy_paste_history_item(i) do
    {_date, command} = do_get_history_item(i)
    Server.paste_command(command)
  end

  @doc false
  def edit_history_item(i) do
    {_date, command} = do_get_history_item(i)
    Server.edit_command(command)
  end

  @doc false
  def find_history_item(match) do
    IExHistory2.configuration(:scope, :local)
    |> do_get_history()
    |> Enum.map(
            fn {_, command} ->
              if String.starts_with?(String.replace(command, ~r/ +/, ""), match),
                do: command,
                else: []
      end)
      |> List.flatten()
      |> List.last()
      |> then(fn(nil) -> {:error, :not_found}
                (val) -> {:ok, val} end)
  end
  
  @doc false
  def clear() do
    if IExHistory2.configuration(:scope, :local) != :global do
      Server.clear()
    else
      (IExHistory2.get_log_path() <> "/erlang-shell*")
      |> Path.wildcard()
      |> Enum.each(fn file -> File.rm(file) end)
    end
  end

  @doc false
  def clear_history(range) do
    cond do
      IExHistory2.configuration(:scope, :local) != :global ->
        Server.clear_history(range)

      range == :all ->
        (IExHistory2.get_log_path() <> "/erlang-shell*")
        |> Path.wildcard()
        |> Enum.each(fn file -> File.rm(file) end)

      true ->
        nil
    end
  end

  @doc false
  def stop_clear() do
    if IExHistory2.configuration(:scope, :local) != :global do
      Server.stop_clear()
    else
      (IExHistory2.get_log_path() <> "/erlang-shell*")
      |> Path.wildcard()
      |> Enum.each(fn file -> File.rm(file) end)
    end
  end

  @doc false
  def state(how \\ :normal) do
    my_node = IExHistory2.my_real_node()
    server_state = Server.get_state()

    count =
      if is_map(server_state) do
        Enum.map(
          server_state,
          fn
            {_pid, %{beam_node: node, size: size}} when node == my_node ->
              [node: node, size: size]

            _ ->
              :ok
          end
        )
        |> Enum.filter(&(&1 != :ok))
        |> List.flatten()
        |> Keyword.get(:size)
      else
        0
      end

    string = "#{IO.ANSI.white()}Current history is #{IO.ANSI.red()}#{count} #{IO.ANSI.white()}commands in size"

    if how == :pretty do
      IO.puts("#{string}")
    else
      if how == :number, do: count, else: string
    end
  end

  @doc false
  def raw_state() do
    Server.get_state()
  end

  @doc false
  def raw_state(pid) do
    Map.get(Server.get_state(), pid)
  end

  @doc false
  def does_current_scope_match?(new_scope) do
    case Server.get_state() do
      %{scope: scope} -> scope == new_scope
      _ -> new_scope
    end
  end

  @doc false
  def infinity_limit(), do: @infinity_limit

  @doc false
  def send_message(message) do
    Server.send_message(message)
  end

  @doc false
  def do_get_history_registration(store_name, start, stop) do
    quantity = stop - start

    IExHistory2.Store.get_all_objects(store_name)
    |> Enum.sort(:asc)
    |> Enum.map(fn {_date, cmd} -> String.trim(cmd) end)
    |> Enum.slice(start, quantity)
    |> Enum.reverse()
  end

  defp do_initialize({:ok, true, scope, node}) do
    local_shell_state = create_local_shell_state(scope, node)
    register_or_start_tracer_service(local_shell_state)
  end

  defp do_initialize(_), do: :not_ok

  defp do_get_history_item(i) when i >= 1, do: IExHistory2.configuration(:scope, :local) |> do_get_history() |> Enum.at(i - 1)

  defp do_get_history_item(i), do: do_get_history_range(state(:number) + i, :stop)

  defp do_get_history_range(:start, stop), do: do_get_history_range(1, stop)

  defp do_get_history_range(start, :stop), do: do_get_history_range(start, state(:number))

  defp do_get_history_range(start, stop) when start >= 1 and stop > start do
    start = start - 1
    stop = stop
    quantity = stop - start
    history_size = state(:number)

    if start > history_size or stop > history_size,
      do: raise(%ArgumentError{message: "Values out of range, only #{history_size} entries exist"})

    IExHistory2.configuration(:scope, :local)
    |> do_get_history()
    |> Enum.slice(start, quantity)
  end

  defp do_get_history_range(_start, _stop), do: raise(%ArgumentError{message: "Values out of range, only #{state(:number)} entries exist"})

  defp pp_history_items(items, start) do
    Enum.reduce(items, start, fn {date, command}, count ->
      display_formatted_date(count, date, command)
      count + 1
    end)
  end

  defp clean_command(command) do
    clean_command(command, get_command_width())
  end

  defp clean_command(command, display_width) when byte_size(command) > display_width do
    String.replace(command, ~r/\s+/, " ")
    |> String.slice(0, display_width)
    |> Kernel.<>(" ...")
  end

  defp clean_command(command, _) do
    String.replace(command, ~r/\s+/, " ")
  end

  defp get_command_width() do
    IExHistory2.configuration(:command_display_width, nil)
  end

  defp display_formatted_date(count, date, command, match \\ "") do
    command = clean_command(command)
    show_date? = IExHistory2.configuration(:show_date, true)
    scope = IExHistory2.configuration(:scope, :local)

    if show_date? && scope != :global,
      do: IO.puts("#{color(:index)}#{count}: #{match}#{color(:date)}#{date}: #{color(:command)}#{command}"),
      else: IO.puts("#{color(:index)}#{count}: #{match}#{color(:command)}#{command}")
  end

  @doc false
  def color(what), do: IExHistory2.get_color_code(what)

  defp set_group_history(state) do
    :rpc.call(:erlang.node(Process.group_leader()), Application, :put_env, [:kernel, :shell_history, state])
  end

  defp history_item_contains?(command, match, closeness) do
    lc_command = String.downcase(command)
    lc_match = String.downcase(match)
    cond do 
      String.contains?(command, match) -> 1
      closeness in [:ignore_case, :approximate] && String.contains?(lc_command, lc_match) -> 1
      closeness == :approximate -> history_item_may_contain?(lc_command, lc_match) 
      true -> 0
    end
  end

  defp history_item_may_contain?(command, match) do
    String.myers_difference(command, match) 
    |> Enum.filter(&(elem(&1, 0) == :eq))
    |> Enum.map(fn {_, s} -> String.jaro_distance(s, match) end) 
    |> then(fn([]) -> 0
           (prob) -> Enum.max(prob)
       end)
  end
  
  defp do_get_history(:global) do
    hide_string =
      if IExHistory2.configuration(:hide_history_commands, true),
        do: IExHistory2.module_name(),
        else: @random_string

    :rpc.call(:erlang.node(:erlang.group_leader()), :group_history, :load, [])
    |> Enum.map(fn cmd -> {"undefined", String.trim(to_string(cmd))} end)
    |> Enum.filter(fn {_date, cmd} -> not String.contains?(cmd, IExHistory2.exec_name()) && not String.starts_with?(cmd, hide_string) end)
    |> Enum.reverse()
  end

  defp do_get_history(_) do
    store_name = Process.get(:history_events_store_name)

    IExHistory2.Store.get_all_objects(store_name)
    |> Enum.sort(:asc)
    |> Enum.map(fn {date, cmd} -> {unix_to_date(date), String.trim(cmd)} end)
  end

  defp create_local_shell_state(scope, my_node) do
    str_label =
      if scope in [:node, :local],
        do: "#{scope}_#{my_node}",
        else: Atom.to_string(scope)

    store_name = String.to_atom("#{@store_name}_#{str_label}")
    store_filename = "#{IExHistory2.get_log_path()}/history_#{str_label}.dat"
    Process.put(:history_events_store_name, store_name)
    server_pid = :group.whereis_shell()
    server_node = :erlang.node(server_pid)
    beam_node = :erlang.node(:erlang.group_leader())
    user_driver_group = :rpc.call(beam_node, :user_drv, :whereis_group, [])
    user_driver = :rpc.call(beam_node, Process, :whereis, [:user_drv])

    %{
      store_name: store_name,
      store_filename: store_filename,
      server_pid: server_pid,
      shell_pid: self(),
      size: 0,
      prepend_ids: nil,
      pending_command: "",
      node: server_node,
      beam_node: beam_node,
      user_driver: user_driver,
      port: :port,
      success_count: nil,
      last_command: nil,
      queue: {0, []},
      user_driver_group: user_driver_group,
      scan_direction: nil,
      last_direction: :none,
      keystroke_monitor_pid: nil,
      last_scan_command: "",
      paste_buffer: "",
      data_in_editor: ""
    }
  end

  defp register_or_start_tracer_service(local_shell_state) do
    if Process.whereis(Server) == nil do
      do_start_tracer_service()
    end

    Server.register_new_shell(local_shell_state)
  end

  defp do_start_tracer_service() do
    scope = IExHistory2.configuration(:scope, :local)
    hide_history_cmds = IExHistory2.configuration(:hide_history_commands, true)
    prepend_ids? = IExHistory2.configuration(:prepend_identifiers, true)
    save_invalid = IExHistory2.configuration(:save_invalid_results, true)
    key_buffer_history = IExHistory2.configuration(:key_buffer_history, true)

    real_limit =
      case IExHistory2.configuration(:history_limit, :infinity) do
        :infinity -> @infinity_limit
        limit -> limit
      end

    process_info_state =
      %{
        scope: scope,
        hide_history_commands: hide_history_cmds,
        store_count: 0,
        limit: real_limit,
        module_alias: nil,
        prepend_identifiers: prepend_ids?,
        save_invalid_results: save_invalid,
        key_buffer_history: key_buffer_history
      }

    Server.start_link(process_info_state)
  end

  defp unix_to_date(unix) do
    DateTime.from_unix!(round(unix / 1000))
    |> DateTime.to_string()
    |> String.replace("Z", "")
  end
end

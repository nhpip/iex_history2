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

defmodule History.Events do

  @infinity_limit 3000  # So dets doesn't get too big, may find a better way
  @store_name "store_history_events"
  @random_string "adarwerwvwvevwwerxrwfx"

  alias History.Events.Server

  @doc false
  def initialize(config) do
    scope = Keyword.get(config, :scope, :local)
    if scope != :global do
      set_group_history(:disabled)
      History.persistence_mode(scope) |> do_initialize()
      config
    else
      set_group_history(:enabled)
      config
    end
  end

  @doc false
  def get_history() do
    History.configuration(:scope, :local)
    |> do_get_history()
    |> pp_history_items(1)
    nil 
  end

  @doc false
  def get_history_item(match) when is_binary(match) do
    History.configuration(:scope, :local)
    |> do_get_history()
    |> Enum.reduce(1,
         fn({date, command}, count) ->
            if String.contains?(command, match) do
              display_formatted_date(count, date, command)
              count + 1
            else
              count + 1
            end
    end)
  end

  @doc false
  def get_history_item(i) when i >= 1 do
    {date, command} = do_get_history_item(i)
    display_formatted_date(i, date, String.replace(command, ~r/\s+/, " "))
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
    {result, _} = Code.eval_string(command, History.get_bindings())

    if History.configuration(:scope, :local) == :global,
       do: :rpc.call(:erlang.node(:erlang.group_leader()), :group_history, :add, [to_charlist(command)]),
       else: Server.save_history_command(command)
    result
  end

  @doc false
  def copy_paste_history_item(i) do
    {_date, command} = do_get_history_item(i)
    Server.paste_command(String.replace(command, ~r/\s+/, " "))
  end

  @doc false
  def clear() do
    if History.configuration(:scope, :local) != :global do
      Server.clear()
    else
      History.get_log_path() <> "/erlang-shell*"
      |> Path.wildcard()
      |> Enum.each(fn file -> File.rm(file) end)
    end
  end

  @doc false
  def clear_history(range) do
    if History.configuration(:scope, :local) != :global do
      Server.clear_history(range)
    else
      if range == :all, do:
        History.get_log_path() <> "/erlang-shell*"
        |> Path.wildcard()
        |> Enum.each(fn file -> File.rm(file) end)
    end
  end

  @doc false
  def stop_clear() do
    if History.configuration(:scope, :local) != :global do
      Server.stop_clear()
    else
      History.get_log_path() <> "/erlang-shell*"
      |> Path.wildcard()
      |> Enum.each(fn file -> File.rm(file) end)
    end
  end

  @doc false
  def state(how \\ :normal) do
    my_node = History.my_real_node()
    count = case Server.get_state() do
      %{} = map ->
        Enum.map(map,
              fn({_pid, %{beam_node: node, size: size}}) ->
                if node ==  my_node,
                   do: [node: node, size: size],
                   else: :ok;
              (_) -> :ok end)
        |> Enum.filter(&(&1!=:ok)) |> List.flatten() |> Keyword.get(:size)
      _ ->
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
    History.Store.get_all_objects(store_name)
    |> Enum.sort(:asc)
    |> Enum.map(fn({_date, cmd}) -> String.trim(cmd) end)
    |> Enum.slice(start, quantity)
    |> Enum.reverse()
  end

  defp do_initialize({:ok, true, scope, node}) do
    local_shell_state = create_local_shell_state(scope, node)
    register_or_start_tracer_service(local_shell_state)
  end

  defp do_initialize(_), do: :not_ok

  defp do_get_history_item(i) when i >= 1, do:
    History.configuration(:scope, :local) |> do_get_history() |> Enum.at(i - 1)

  defp do_get_history_item(i), do:
    do_get_history_range(state(:number) + i, :stop)

  defp do_get_history_range(:start, stop), do:
    do_get_history_range(1, stop)

  defp do_get_history_range(start, :stop), do:
    do_get_history_range(start, state(:number))

  defp do_get_history_range(start, stop) when start >= 1 and stop > start do
    start = start - 1
    stop = stop
    quantity = stop - start
    history_size = state(:number)
    if start > history_size or stop > history_size,
       do: raise(%ArgumentError{message: "Values out of range, only #{history_size} entries exist"})
    History.configuration(:scope, :local)
    |> do_get_history()
    |> Enum.slice(start, quantity)
  end

  defp do_get_history_range(_start, _stop), do:
    raise(%ArgumentError{message: "Values out of range, only #{state(:number)} entries exist"})

  defp pp_history_items(items, start) do
    display_width = get_command_width()
    Enum.reduce(items, start,
      fn({date, command}, count) ->
        new_command = if String.length(command) > display_width,
                          do: String.slice(command, 0, display_width) <> " .....",
                          else: command
        display_formatted_date(count, date, String.replace(new_command, ~r/\s+/, " "))
        count + 1
      end)
      nil
  end

  defp get_command_width() do
    History.configuration(:command_display_width, nil)
  end

  defp display_formatted_date(count, date, command) do
    show_date? = History.configuration(:show_date, true)
    scope = History.configuration(:scope, :local)
    if show_date? && scope != :global,
       do: IO.puts("#{color(:index)}#{count}: #{color(:date)}#{date}: #{color(:command)}#{command}"),
       else: IO.puts("#{color(:index)}#{count}: #{color(:command)}#{command}")
  end

  defp color(what), do:
    History.get_color_code(what)

  defp set_group_history(state), do:
    :rpc.call(:erlang.node(Process.group_leader()), Application, :put_env, [:kernel, :shell_history, state])

  defp do_get_history(:global) do
    hide_string = if History.configuration(:hide_history_commands, true),
                      do: History.module_name(),
                      else: @random_string
    :rpc.call(:erlang.node(:erlang.group_leader()), :group_history, :load, [])
    |> Enum.map(fn cmd -> {"undefined", String.trim(to_string(cmd))} end)
    |> Enum.filter(fn {_date, cmd} -> not String.contains?(cmd, History.exec_name()) end)
    |> Enum.filter(fn {_date, cmd} -> not String.starts_with?(cmd, hide_string) end)
    |> Enum.reverse()
  end

  defp do_get_history(_) do
    store_name = Process.get(:history_events_store_name)
    History.Store.get_all_objects(store_name)
    |> Enum.sort(:asc)
    |> Enum.map(fn({date, cmd}) -> {unix_to_date(date), String.trim(cmd)} end)
  end

  defp create_local_shell_state(scope, my_node) do
    str_label = if scope in [:node, :local],
                   do: "#{scope}_#{my_node}",
                   else: Atom.to_string(scope)
    store_name = String.to_atom("#{@store_name}_#{str_label}")
    store_filename = "#{History.get_log_path()}/history_#{str_label}.dat"
    Process.put(:history_events_store_name, store_name)
    server_pid = :group.whereis_shell()
    server_node = :erlang.node(server_pid)
    beam_node = :erlang.node(:erlang.group_leader())
    user_driver_group = :rpc.call(beam_node, :user_drv, :whereis_group, [])
    user_driver =  :rpc.call(beam_node, Process, :whereis, [:user_drv])

    %{store_name: store_name, store_filename: store_filename, server_pid: server_pid, shell_pid: self(),
      size: 0, prepend_ids: nil, pending_command: "",  node: server_node, beam_node: beam_node, user_driver: user_driver,
      port: :port, success_count: nil, last_command: nil, queue: {0, []}, user_driver_group: user_driver_group,
      scan_direction: nil, last_direction: :up, key_buffer_history_pid: nil, last_scan_command: ""}
  end

  defp register_or_start_tracer_service(local_shell_state) do
    if Process.whereis(Server) == nil do
      do_start_tracer_service()
    end
    Server.register_new_shell(local_shell_state)
  end

  defp do_start_tracer_service() do
    scope = History.configuration(:scope, :local)
    hide_history_cmds = History.configuration(:hide_history_commands, true)
    prepend_ids? = History.configuration(:prepend_identifiers, true)
    save_invalid = History.configuration(:save_invalid_results, true)
    key_buffer_history = History.configuration(:key_buffer_history, true)
    real_limit = if (limit = History.configuration(:history_limit, :infinity)) == :infinity, do: @infinity_limit, else: limit
    process_info_state =
          %{scope: scope, hide_history_commands: hide_history_cmds, store_count: 0, limit: real_limit, module_alias: nil,
            prepend_identifiers: prepend_ids?, save_invalid_results: save_invalid, key_buffer_history: key_buffer_history}
    Server.start_link(process_info_state)
  end

  def get_shell_info() do
    user_driver = :rpc.call(:erlang.node(Process.group_leader()), Process, :info, [Process.group_leader()])[:dictionary][:user_drv]
IO.inspect(user_driver)
    link_info = :rpc.call(:erlang.node(Process.group_leader()), Process, :info, [user_driver])[:links]
IO.inspect(link_info)
    port = Enum.filter(link_info, &is_port(&1)) |> hd()
    {user_driver, port}
  end

  defp unix_to_date(unix), do:
    DateTime.from_unix!(round(unix/1000)) |> DateTime.to_string() |> String.replace("Z", "")

end

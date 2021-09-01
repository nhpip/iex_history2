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

  @size_check_interval 60 * 1000
  @table_limit_exceeded_factor 0.1
  @infinity_limit 3000  # So dets doesn't get too big, may find a better way
  @store_name "store_history_events"
  @tracer_reg_name :history_tracer_handler
  @random_string "adarwerwvwvevwwerxrwfx"

  @doc false
  def initialize(config) do
    scope = Keyword.get(config, :scope, :local)
    if scope != :global do
      Application.put_env(:kernel, :shell_history, :disabled)
      History.persistence_mode(scope) |> do_initialize()
      config
    else
      Application.put_env(:kernel, :shell_history, :enabled)
      config
    end
  end

  @doc false
  def get_history() do
    History.configuration(:scope, :local)
    |> do_get_history()
    |> Enum.reduce(1,
         fn({date, command}, count) ->
           display_formatted_date(count, date, command)
            count + 1
    end)
    :ok
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
  def get_history_item(i) do
    {date, command} = do_get_history_item(i)
    display_formatted_date(i, date, command)
  end

  @doc false
  def execute_history_item(i) do
    {_date, command} = do_get_history_item(i)
    {result, _} = Code.eval_string(command, History.get_bindings())

    if History.configuration(:scope, :local) == :global,
       do: :rpc.call(:erlang.node(:erlang.group_leader()), :group_history, :add, [to_charlist(command)]),
       else: send_msg({:item, self(), command})
    result
  end

  @doc false
  def clear() do
    if History.configuration(:scope, :local) != :global do
      send_msg({:clear, self()})
      wait_rsp(:ok_done)
    else
      History.get_log_path() <> "/erlang-shell*"
      |> Path.wildcard()
      |> Enum.each(fn file -> File.rm(file) end)
    end
  end

  @doc false
  def stop_clear() do
    if History.configuration(:scope, :local) != :global do
      send_msg({:stop_clear, self()})
      wait_rsp(:ok_done)
    else
      History.get_log_path() <> "/erlang-shell*"
      |> Path.wildcard()
      |> Enum.each(fn file -> File.rm(file) end)
    end
  end

  @doc false
  def state(pretty \\ false) do
    my_node = History.my_real_node()
    send_msg({:state, self()})
    count = case wait_rsp({:state, :_}) do
      {:state, %{} = map} ->
        Enum.map(map,
              fn({_pid, %{node: node, size: size}}) ->
                if node ==  my_node,
                   do: [node: node, size: size],
                   else: :ok;
              (_) -> :ok end)
        |> Enum.filter(&(&1!=:ok)) |> List.flatten() |> Keyword.get(:size)
      _ ->
        0
    end
    string = "#{IO.ANSI.white()}Current history is #{IO.ANSI.red()}#{count} #{IO.ANSI.white()}commands in size"
    if pretty, do: IO.puts("#{string}"), else: string
  end

  @doc false
  def raw_state() do
    send_msg({:state, self()})
    wait_rsp({:state, :_})
   end

  @doc false
  def does_current_scope_match?(new_scope) do
    send_msg({:state, self()})
    case wait_rsp({:state, :_}) do
      {:state, state} -> state.scope == new_scope
      _ -> new_scope
    end
  end

  @doc false
  def send_msg(what) do
    try do
      send(Process.whereis(@tracer_reg_name), what)
    catch
      _,_ -> :error
    end
  end

  @doc false
  def infinity_limit(), do: @infinity_limit

  defp do_initialize({:ok, true, scope, node}) do
    db_labels = init_stores(scope, node)
    start_tracer_service(db_labels)
  end

  defp do_initialize(_), do: :not_ok

  defp do_get_history_item(i), do: History.configuration(:scope, :local) |> do_get_history() |> Enum.at(i - 1)

  defp display_formatted_date(count, date, command) do
    show_date? = History.configuration(:show_date, true)
    scope = History.configuration(:scope, :local)
    if show_date? && scope != :global,
       do: IO.puts("#{color(:index)}#{count}: #{color(:date)}#{date}: #{color(:command)}#{command}"),
       else: IO.puts("#{color(:index)}#{count}: #{color(:command)}#{command}")
  end

  defp color(what), do:
    History.get_color_code(what)

  defp do_get_history(:global) do
    hide_string = if History.configuration(:hide_history_commands, true),
                      do: History.module_name(),
                      else: @random_string
    :rpc.call(:erlang.node(:erlang.group_leader()), :group_history, :load, [])
    |> Enum.map(fn cmd -> {"undefined", String.trim(to_string(cmd))} end)
    |> Enum.filter(fn {_date, cmd} -> not String.starts_with?(cmd, History.exec_name()) end)
    |> Enum.filter(fn {_date, cmd} -> not String.starts_with?(cmd, hide_string) end)
    |> Enum.reverse()
  end

  defp do_get_history(_) do
    store_name = Process.get(:history_events_store_name)
    History.Store.get_all_objects(store_name)
    |> Enum.sort(:asc)
    |> Enum.map(fn({date, cmd}) -> {unix_to_date(date), String.trim(cmd)} end)
  end

  defp init_stores(scope, my_node) do
    str_label = if scope in [:node, :local],
                   do: "#{scope}_#{my_node}",
                   else: Atom.to_string(scope)
    store_name = String.to_atom("#{@store_name}_#{str_label}")
    store_filename = "#{History.get_log_path()}/history_#{str_label}.dat"
    Process.put(:history_events_store_name, store_name)
    server_node = :erlang.node(:erlang.group_leader())
    %{store_name: store_name, store_filename: store_filename, node: server_node, size: 0}
  end

  defp start_tracer_service(db_config) do
    if Process.whereis(@tracer_reg_name) == nil do
      do_start_tracer_service(self())
    end
    register_with_tracer_service(db_config)
  end

  defp do_start_tracer_service(shell_pid) do
    scope = History.configuration(:scope, :local)
    hide_history_cmds = History.configuration(:hide_history_commands, true)
    real_limit = if (limit = History.configuration(:history_limit, :infinity)) == :infinity, do: @infinity_limit, else: limit
    spawn(fn ->
      Process.register(self(), @tracer_reg_name)
      send(shell_pid, :started)
      Process.send_after(self(), :size_check, @size_check_interval)
      tracer_loop(%{scope: scope, hide_history_commands: hide_history_cmds, store_count: 0, limit: real_limit})
    end)
    wait_rsp(:started)
  end

  defp register_with_tracer_service(db_config) do
    server_pid = Process.info(self())[:dictionary][:iex_server]
    send_msg({:register, self(), server_pid, db_config})
  end

  defp tracer_loop(%{scope: scope, store_count: store_count} = process_info) do
    receive do
      {:trace, _, :send, {:eval, _, command, _}, shell_pid} ->
        save_traced_command(command, shell_pid, process_info)
        tracer_loop(process_info)

      {:item, shell_pid, command} ->
        save_traced_command(command, shell_pid, process_info)
        tracer_loop(process_info)

      {:register, shell_pid, server_pid, db_config} ->
        if Map.get(process_info, shell_pid) == nil do
          new_process_info = Map.put(process_info, shell_pid, db_config)
          new_process_info = Map.put(new_process_info, db_config.node, shell_pid)
          store_count = History.Store.open_store(db_config.store_name, db_config.store_filename, scope, store_count)
          :erlang.trace(server_pid, true, [:send])
          Node.monitor(db_config.node, true)
          Process.monitor(shell_pid)
          tracer_loop(%{new_process_info | store_count: store_count})
        else
          tracer_loop(process_info)
        end

      {:new_history_limit, new_value} ->
        new_process_info = %{process_info | limit: new_value}
        apply_table_limits(new_process_info)
        tracer_loop(new_process_info)

      {:hide_history_commands, value} ->
        tracer_loop(%{process_info | hide_history_commands: value})

      {:DOWN, _, :process, shell_pid, :noproc} ->
        case Map.get(process_info, shell_pid) do
          %{store_name: store_name} ->
            store_count = History.Store.close_store(store_name, scope, store_count)
            new_process_info = Map.delete(process_info, shell_pid)
            tracer_loop(%{new_process_info | store_count: store_count})
          _ ->
            tracer_loop(process_info)
        end

      {:nodedown, node} ->
        case Map.get_and_update(process_info, node, fn _ -> :pop end) do
          {nil, _} ->
            tracer_loop(process_info)

          {pid, new_process_info} ->
            {%{store_name: store_name}, newer_process_info} = Map.get_and_update(new_process_info, pid, fn _ -> :pop end)
            store_count = History.Store.close_store(store_name, scope, store_count)
            tracer_loop(%{newer_process_info | store_count: store_count})
        end

      {:clear, pid} ->
        case Map.get(process_info, pid) do
          %{store_name: store_name} ->
            History.Store.delete_all_objects(store_name)
            send(pid, :ok_done)
            tracer_loop(process_info)
          _ ->
            send(pid, :ok_done)
            tracer_loop(process_info)
        end

      {:stop_clear, pid} ->
        Enum.each(process_info,
                fn({key, value}) when is_pid(key) ->
                    History.Store.delete_all_objects(value.store_name)
                    History.Store.close_store(value.store_name);
                (_) -> :ok
        end)
        send(pid, :ok_done)

      {:state, pid} ->
        new_process_info = Enum.map(process_info,
                  fn({pid, %{store_name: name} = map}) ->
                      {pid, %{map | size: History.Store.info(name, :size)}};
                    (x)-> x
                  end)
        |> Enum.into(%{})
        send(pid, {:state, new_process_info})
        tracer_loop(process_info)

      :size_check ->
        apply_table_limits(process_info)
        Process.send_after(self(), :size_check, @size_check_interval)
        tracer_loop(process_info)

      _ ->
        tracer_loop(process_info)

    end
  end

  defp save_traced_command(command, shell_pid, process_info), do:
    do_save_traced_command(String.trim(command), shell_pid, process_info)

  defp do_save_traced_command("", _shell_pid, _process_info), do: :ok

  defp do_save_traced_command(command, shell_pid, %{hide_history_commands: true} = process_info) do
    do_not_save = String.starts_with?(command, History.module_name())
    case Map.get(process_info, shell_pid) do
      _ when do_not_save == true ->
        :ok
      data when is_map(data) ->
        History.Store.save_data(data.store_name, {System.os_time(:second), command})
      _ ->
        :ok
    end
  end

  defp do_save_traced_command(command, shell_pid, process_info) do
    do_not_save = String.starts_with?(command, History.exec_name())
    case Map.get(process_info, shell_pid) do
      _ when do_not_save == true ->
        :ok
      data when is_map(data) ->
        History.Store.save_data(data.store_name, {System.os_time(:second), command})
      _ ->
        :ok
    end
  end

  defp apply_table_limits(%{limit: limit} = process_info) do
    Enum.each(process_info,
      fn({pid, %{store_name: name} = _map}) ->
        current_size = History.Store.info(name, :size)
        if current_size >= limit,
           do: do_apply_table_limits(pid, name, current_size, limit)
        (x)-> x
      end)
  end

  defp do_apply_table_limits(pid, name, current_size, limit) do
    table_name = inspect(pid) |> String.to_atom()
    if :ets.info(table_name) == :undefined do
      :ets.new(table_name, [:named_table, :ordered_set, :public])
      History.Store.foldl(name, [], fn({key, _}, _) -> :ets.insert(table_name, {key, :ok}) end)
    end
    remove = round(limit * @table_limit_exceeded_factor) + current_size - limit
    Enum.reduce(1..remove, :ets.first(table_name),
            fn(_, key) ->
                :ets.delete(table_name, key)
                History.Store.delete_data(name, key)
                :ets.first(table_name)
            end)
  end

  defp unix_to_date(unix), do:
    DateTime.from_unix!(unix) |> DateTime.to_string() |> String.replace("Z", "")

  defp wait_rsp(what) do
    receive do
      ^what -> :ok;
      {:state, state} -> {:state, state}
    after
      1000 -> :nok
    end
  end

end

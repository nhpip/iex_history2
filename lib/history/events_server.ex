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

defmodule History.Events.Server do

  @size_check_interval 60 * 1000
  @table_limit_exceeded_factor 0.1

  @history_buffer_size 75
  @save_immediate_buffer_duplicates false
  @history_scan_key  21     # ctrl+u
  @history_down_key 11    # ctrl+k
  @enter_key '\r'

  use GenServer


  @doc false
  def register_new_shell(shell_config) do
    GenServer.cast(__MODULE__, {:register_new_shell, shell_config})
  end

  @doc false
  def save_history_command(command) do
    GenServer.cast(__MODULE__, {:command_item, self(), command})
  end

  @doc false
  def paste_command(command) do
    GenServer.cast(__MODULE__, {:paste_command, self(), command})
  end

  @doc false
  def clear() do
    GenServer.call(__MODULE__, {:clear, self()})
  end

  @doc false
  def clear_history(range) do
    GenServer.call(__MODULE__, {:clear_history, range})
  end

  @doc false
  def stop_clear() do
    GenServer.call(__MODULE__, {:stop_clear, self()})
  end

  @doc false
  def get_state() do
    if Process.whereis(__MODULE__) != nil,
      do: GenServer.call(__MODULE__, :get_state),
      else: false
  end

  @doc false
  def send_message(message) do
    GenServer.cast(__MODULE__, message)
  end

  @doc false
  def start_link(process_info) do
    GenServer.start_link(__MODULE__, [process_info], name: __MODULE__)
  end


  @doc false
  def init([process_info]) do
    Process.send_after(self(), :size_check, @size_check_interval)
    {:ok, process_info}
  end

  def handle_call({:clear, shell_pid}, _from, process_info) do
    case Map.get(process_info, shell_pid) do
      %{store_name: store_name} = shell_info ->
        History.Store.delete_all_objects(store_name)
        {:reply, :ok_done, %{process_info | shell_pid => %{shell_info | queue: {0, []}}}}
      _ ->
        {:reply, :ok_done, process_info}
    end
  end

  def handle_call({:clear_history, range}, _from, process_info) do
    new_process_info = %{process_info | limit: range}
    apply_table_limits(new_process_info, :requested)
    {:reply, :ok_done, process_info}
  end

  def handle_call(:stop_clear, _from, process_info) do
      Enum.each(process_info,
        fn({key, value}) when is_pid(key) ->
          History.Store.delete_all_objects(value.store_name)
          History.Store.close_store(value.store_name);
          (_) -> :ok
        end)
      {:stop, :normal, :ok_done, process_info}
  end

  def handle_call(:get_state, _from, process_info) do
    new_process_info = Enum.map(process_info,
                         fn({pid, %{store_name: name} = map}) ->
                            {pid, %{map | size: History.Store.info(name, :size)}};
                           (x)-> x
                         end) |> Enum.into(%{})
    {:reply, new_process_info, process_info}
  end

  def handle_call(_msg, _from, process_info) do
    {:reply, :ok, process_info}
  end


  def handle_cast({:register_new_shell, shell_config}, process_info) do
    new_process_info = do_register_new_shell(shell_config, process_info)
    {:noreply, new_process_info}
  end

  def handle_cast({:paste_command, shell_pid, command}, process_info) do
    paste_command(command, shell_pid, process_info)
    {:noreply, process_info}
  end

  def handle_cast({:new_history_limit, new_value}, process_info) do
    new_process_info = %{process_info | limit: new_value}
    apply_table_limits(new_process_info)
    {:noreply, new_process_info}
  end

  def handle_cast({:key_buffer_history, true}, %{key_buffer_history: false} = process_info) do
    new_process_info =
      Enum.reduce(process_info, process_info,
              fn({shell_pid, shell_config}, process_info) when is_pid(shell_pid) ->
                    {kbh_pid, kbh_queue} = setup_key_buffer_history(shell_config, true)
                    Map.put(process_info, shell_pid, %{shell_config | queue: kbh_queue, key_buffer_history_pid: kbh_pid});
                (_, process_info) ->
                    process_info
              end)
    {:noreply, %{new_process_info | key_buffer_history: true}}
  end

  def handle_cast({:key_buffer_history, false}, %{key_buffer_history: true} = process_info) do
    new_process_info =
      Enum.reduce(process_info, process_info,
              fn({shell_pid, %{group_leader: group_leader, key_buffer_history_pid: kbh_pid} = shell_config}, process_info) when is_pid(shell_pid) ->
                    if is_pid(kbh_pid),
                       do: send(kbh_pid, :exit),
                       else: :erlang.trace(group_leader, false, [:receive])
                    Map.put(process_info, shell_pid, %{shell_config | queue: {0, []}, key_buffer_history_pid: nil});
                (_, process_info) ->
                    process_info
      end)
    {:noreply, %{new_process_info | key_buffer_history: false}}
  end

  def handle_cast({:hide_history_commands, value}, process_info) do
    {:noreply, %{process_info | hide_history_commands: value}}
  end

  def handle_cast({:prepend_identifiers, value}, process_info) do
    {:noreply, %{process_info | prepend_identifiers: value}}
  end

  def handle_cast({:save_invalid_results, value}, process_info) do
    {:noreply, %{process_info | save_invalid_results: value}}
  end

  def handle_cast({:module_alias, value}, process_info) do
    {:noreply, %{process_info | module_alias: value}}
  end

  def handle_cast({:command_item, shell_pid, command}, process_info) do
    new_command = modify_command(command, shell_pid, process_info)
    new_process_info = save_traced_command(new_command, shell_pid, process_info)
    {:noreply, new_process_info}
  end

  def handle_cast(_msg, process_info) do
    {:noreply, process_info}
  end


  def handle_info({:trace, _, :send, {:eval, _, command, _}, shell_pid}, %{module_alias: alias} = process_info) do
    case validate_command(de_alias_command(command, alias), shell_pid, process_info) do
      {true, new_command, new_process_info} ->
        new_process_info = save_traced_command(new_command, shell_pid, new_process_info)
        {:noreply, new_process_info}

      {_, _, new_process_info} ->
        {:noreply, new_process_info}
    end
  end

  def handle_info({:trace, _, :receive, {:evaled, _, %IEx.State{on_eof: :stop_evaluator}}}, process_info) do
    {:noreply, process_info}
  end

  def handle_info({:trace, _, :receive, {:evaled, shell_pid, %IEx.State{} = iex_state}}, process_info) do
    {cache_state, count} =  get_iex_state_cache_and_counter(iex_state)
    new_process_info = last_command_result(count, shell_pid, process_info, cache_state)
    {:noreply, new_process_info}
  end

  ## This a bit odd, the only ctrl key that works is ctrl-u (of course this was chosen because U == up history). Basically the other
  ## ctrl keys are used for other features, or do strange handling on the shell. Basically user_drv.erl and group.erl take control
  ## of keyboard input so when we up/down one finds that the "only" one that doesn't break the output is ctrl-u. Ctrl-k doesn't do much
  ## but is no good for output.
  ##
  ## So what we do is keep in the state of last direction of :up or :down. If we go up ctrl-u will traverse up the history nicely presenting
  ## historic commands to the shell. It knows to go up in the history not based on the ctrl-u been pressed but based on the state, after a single "up" the
  ## state is set to nil (which is assumed to also be up). To go down ctrl-k is pressed, we mark the state as down and then inject a
  ## ctrl-u to user_drv. The ctrl-u is captured by this code, except now the state says go down through history.
  def handle_info({:trace, leader_pid, :receive, {_, {:data, [@history_scan_key]}}}, %{key_buffer_history: true} = process_info) do
    new_process_info = queue_display_handler(leader_pid, process_info, :scan)
    {:noreply, new_process_info}
  end

  def handle_info({:trace, leader_pid, :receive, {_, {:data, [@history_down_key]}}}, %{key_buffer_history: true} = process_info) do
    new_process_info = queue_display_handler(leader_pid, process_info, :initial_down)
    {:noreply, new_process_info}
  end

  def handle_info({:trace, leader_pid, :receive, {_, {:data, @enter_key}}}, process_info) do
    new_process_info = queue_display_handler(leader_pid, process_info, :return)
    {:noreply, new_process_info}
  end

  def handle_info({:DOWN, _, :process, shell_pid, _}, %{scope: scope, store_count: store_count} = process_info) do
    case Map.get(process_info, shell_pid) do
      %{store_name: store_name, key_buffer_history_pid: kbh_pid} ->
        store_count = History.Store.close_store(store_name, scope, store_count)
        new_process_info = Map.delete(process_info, shell_pid)
        Process.exit(kbh_pid, :down)
        {:noreply, %{new_process_info | store_count: store_count}}
      _ ->
        {:noreply, process_info}
    end
  end

  def handle_info({:nodedown, node}, %{scope: scope, store_count: store_count} = process_info) do
    case Map.get_and_update(process_info, node, fn _ -> :pop end) do
      {nil, _} ->
        {:noreply, process_info}

      {pid, new_process_info} ->
        {%{store_name: store_name}, newer_process_info} = Map.get_and_update(new_process_info, pid, fn _ -> :pop end)
        store_count = History.Store.close_store(store_name, scope, store_count)
        {:noreply, %{newer_process_info | store_count: store_count}}
    end
  end

  def handle_info(:size_check, process_info) do
    apply_table_limits(process_info)
    Process.send_after(self(), :size_check, @size_check_interval)
    {:noreply, process_info}
  end

  def handle_info(_msg, process_info) do
    {:noreply, process_info}
  end

  defp get_iex_state_cache_and_counter(iex_state) do
    new_iex_state = Map.from_struct(iex_state)
    state_map = Map.take(new_iex_state, [:cache, :buffer, :counter])
    try do
      state = if state_map.cache == [], do: :empty_cache, else: :ok
      {state, state_map.counter}
    catch
      _,_ ->
        state = if state_map.buffer == "", do: :empty_cache, else: :ok
        {state, state_map.counter}
    end
  end

  defp do_register_new_shell(%{shell_pid: shell_pid,  server_pid: server_pid} = shell_config,
            %{key_buffer_history: key_buffer_history, scope: scope, store_count: store_count} = process_info) do
    if Map.get(process_info, shell_pid) == nil do
      store_count = History.Store.open_store(shell_config.store_name, shell_config.store_filename, scope, store_count)
      Node.monitor(shell_config.node, true)
      Process.monitor(shell_pid)
      :erlang.trace(server_pid, true, [:send, :receive])
      {kbh_pid, kbh_queue} = setup_key_buffer_history(shell_config, key_buffer_history)
      new_process_info = Map.put(process_info, shell_pid, %{shell_config | queue: kbh_queue, key_buffer_history_pid: kbh_pid})
      new_process_info = Map.put(new_process_info, shell_config.node, shell_pid)
      %{new_process_info | store_count: store_count}
    else
      process_info
    end
  end

  defp setup_key_buffer_history(%{group_leader: group_leader, node: my_node, store_name: store_name} = _shell_config, true) do
    my_pid = self()
    if my_node == Node.self() do
      :erlang.trace(group_leader, true, [:receive])
      {nil, setup_key_buffer_history_queue(store_name)}
    else
      {mod, bin, _file} = :code.get_object_code(__MODULE__)
      :rpc.call(my_node, :code, :load_binary, [mod, :nofile, bin])
      queue = setup_key_buffer_history_queue(store_name)
      pid = Node.spawn(my_node,
              fn ->
                  :erlang.trace(group_leader, true, [:receive])
                  remote_key_buffer_history_loop(group_leader, my_pid)
              end)
      {pid, queue}
    end
  end

  defp setup_key_buffer_history(_shell_config, _), do:
    {nil, {0, []}}

  defp setup_key_buffer_history_queue(store_name) do
    current_size = History.Store.info(store_name, :size)
    if current_size > 0 do
      start = min(@history_buffer_size, current_size)
      {0, History.Events.do_get_history_registration(store_name, start * -1, current_size)}
    else
      {0, []}
    end
  end

  defp remote_key_buffer_history_loop(group_leader, dest_pid) do
    receive do
      :exit ->
        :erlang.trace(group_leader, false, [:receive])

      message ->
        send(dest_pid,message)
        remote_key_buffer_history_loop(group_leader, dest_pid)
    end
  end


  defp send_to_shell(user_driver, port, _command, :initial_down) do
    send(user_driver, {port,{:data, [@history_scan_key]}})
  end

  defp send_to_shell(user_driver, port, command, _) do
    send(user_driver, {port,{:data, [to_charlist(command)]}})
  end

  defp paste_command(command, shell_pid, process_info) do
    case Map.get(process_info, shell_pid) do
      %{user_driver: user_driver, port: port} = _shell_config ->
        send_to_shell(user_driver, port, command, nil)

      _ ->
        :ok
    end
  end

  defp last_command_result(_current_count, _shell_pid, %{save_invalid_results: true} = process_info, _), do:
    process_info

  defp last_command_result(current_count, shell_pid, process_info, cache) do
    case Map.get(process_info, shell_pid) do
      %{success_count: nil} = shell_config ->
        %{process_info | shell_pid => %{shell_config | success_count: current_count}}

      %{success_count: val, last_command: last_command, pending_command: "", store_name: store} = shell_config when current_count == val ->
        History.Store.delete_data(store, last_command)
        %{process_info | shell_pid => %{shell_config | last_command: 0}}

      %{success_count: val, queue: queue, last_command: last_command, pending_command: pending, store_name: store} = shell_config when current_count == val and cache == :empty_cache ->
        History.Store.delete_data(store, last_command)
        %{process_info | shell_pid => %{shell_config | last_command: 0, success_count: current_count, queue: queue_insert(pending, queue)}}

      %{success_count: val} when current_count == val ->
        process_info

      %{success_count: val} = shell_config when current_count > val ->
        %{process_info | shell_pid => %{shell_config | last_command: 0, success_count: current_count}}

      _ ->
        process_info
    end
  end

  defp queue_display_handler(leader_pid, process_info, operation) do
    case Enum.find(process_info, fn({k,v}) -> is_pid(k) && v.group_leader == leader_pid end) do
      {shell_pid,  %{queue: {_sp, queue}} = shell_config} when operation == :return ->
        %{process_info | shell_pid => %{shell_config | queue: {0, queue}, scan_direction: nil}}

      {shell_pid,  %{user_driver: user_driver, port: port} = shell_config} when operation == :initial_down ->
        send_to_shell(user_driver, port, nil, :initial_down)
        %{process_info | shell_pid => %{shell_config | scan_direction: :down}}

      {_, %{queue: {_sp, []}}} ->
        process_info

      {shell_pid,  %{queue: {sp, queue}, user_driver: user_driver, port: port, scan_direction: scan_direction, last_direction: last_direction} = shell_config} ->
        queue_size = Enum.count(queue)
        direction = if scan_direction == :down, do: :down, else: :up
        search_pos = get_search_position(sp, queue_size, last_direction, direction)

        if search_pos != nil do
          actual_search_pos = if search_pos == 0, do: 1, else: search_pos - 1
          {_, command} = Enum.fetch(queue, actual_search_pos)
          send_to_shell(user_driver, port, String.replace(command, ~r/\s+/, " "), operation)
          %{process_info | shell_pid => %{shell_config | queue: {search_pos, queue}, scan_direction: nil, last_direction: direction}}
        else
          %{process_info | shell_pid => %{shell_config | scan_direction: nil, last_direction: direction}}
        end

      _ ->
        process_info
    end
  end

  defp get_search_position(0, _size, :up, :up), do: 1
  defp get_search_position(current_value, size, :up, :up) when current_value >= size, do: current_value
  defp get_search_position(current_value, _size, :up, :up), do: current_value + 1

  defp get_search_position(0, _size, :down, :down), do: nil
  defp get_search_position(1, _size, :down, :down), do: nil
  defp get_search_position(current_value, _size, :down, :down), do: current_value - 1

  defp get_search_position(0, _size, :up, :down), do: nil
  defp get_search_position(1, _size, :up, :down), do: nil
  defp get_search_position(current_value, size, :up, :down) when current_value >= size - 1, do: current_value - 1
  defp get_search_position(current_value, _size, :up, :down), do: current_value - 1

  defp get_search_position(0, _size, :down, :up), do: 1
  defp get_search_position(current_value, _size, :down, :up), do: current_value + 1


  defp queue_insert(command, {_, []}), do:
    do_queue_insert(command, [])

  defp queue_insert(command, {_, queue}) do
    if @save_immediate_buffer_duplicates do
      do_queue_insert(command, queue)
    else
      [last_command | _] = queue
      if last_command != command,
         do: do_queue_insert(command, queue),
         else: {0, queue}
    end
  end

  defp do_queue_insert(command, queue) do
    size = Enum.count(queue)
    if size >= @history_buffer_size do
      queue = Enum.take(queue, size-1)
      {0, [command | queue]}
    else
      {0, [command | queue]}
    end
  end

  defp validate_command(command, shell_pid, process_info) do
    case Map.get(process_info, shell_pid) do
      shell_config when is_map(shell_config) ->
        do_validate_command(command, shell_config, process_info, shell_pid)
      _ ->
        process_info
    end
  end

  defp do_validate_command(command, %{pending_command: pending} = shell_config, process_info, shell_pid) do
    if is_command_valid?(command) do
      {true, command, %{process_info | shell_pid => %{shell_config | pending_command: ""}}}
    else
      new_command = pending <> command
      if is_command_valid?(new_command) do
        {true, new_command, %{process_info | shell_pid => %{shell_config | pending_command: ""}}}
      else
        new_pending = String.replace(new_command, "\n", "")
        {false, nil, %{process_info | shell_pid => %{shell_config | pending_command: new_pending}}}
      end
    end
  end

  defp is_command_valid?(command) do
    try do
      test_command = find_invalid_comments(command)
      Code.format_string!(test_command)
      true
    catch
      _,_ -> false
    end
  end

  defp find_invalid_comments(command) do
    trimmed = String.trim_leading(command)
    if String.starts_with?(trimmed, ["#PID", "#Ref"]),
       do: String.replace_leading(trimmed, "#", ""),
       else: command
  end

  defp save_traced_command(command, shell_pid, process_info), do:
    do_save_traced_command(String.trim(command), shell_pid, process_info)

  defp do_save_traced_command("", _shell_pid, process_info), do: process_info

  defp do_save_traced_command(command, shell_pid, %{hide_history_commands: true, prepend_identifiers: prepend_ids?} = process_info) do
    {_, identifiers} = save_and_find_history_x_identifiers(command, prepend_ids?)
    do_not_save = String.contains?(command, History.exclude_from_history())
    case Map.get(process_info, shell_pid) do
      %{queue: queue} = shell_config when do_not_save == true ->
        %{process_info | shell_pid => %{shell_config | prepend_ids: identifiers, queue: queue_insert(command, queue)}}

      %{queue: queue} = shell_config ->
        key = System.os_time(:millisecond)
        History.Store.save_data(shell_config.store_name, {key, command})
        %{process_info | shell_pid => %{shell_config | prepend_ids: nil, last_command: key, queue: queue_insert(command, queue)}}

      _ ->
        process_info
    end
  end

  defp do_save_traced_command(command, shell_pid, %{prepend_identifiers: prepend_ids?} = process_info) do
    {do_not_save, identifiers} = save_and_find_history_x_identifiers(command, prepend_ids?)
    case Map.get(process_info, shell_pid) do
      %{queue: queue} = shell_config when do_not_save == true ->
        %{process_info | shell_pid => %{shell_config | prepend_ids: identifiers, queue: queue_insert(command, queue)}}

      %{queue: queue} = shell_config ->
        key = System.os_time(:millisecond)
        History.Store.save_data(shell_config.store_name, {key, command})
        %{process_info | shell_pid => %{shell_config | prepend_ids: nil, last_command: key, queue: queue_insert(command, queue)}}

      _ ->
        process_info
    end
  end

  defp apply_table_limits(%{limit: limit} = process_info, type \\ :automatic) do
    Enum.each(process_info,
      fn({pid, %{store_name: name} = _map}) ->
        current_size = History.Store.info(name, :size)
        limit = if limit == :all, do: current_size, else: limit
        if current_size >= limit && type == :automatic,
           do: do_apply_table_limits(pid, name, current_size, limit, type)
        if type == :requested,
          do: do_apply_table_limits(pid, name, current_size, limit, type)
        (x)-> x
      end)
  end

  defp do_apply_table_limits(pid, name, current_size, limit, type) do
    table_name = inspect(pid) |> String.to_atom()
    if :ets.info(table_name) == :undefined do
      :ets.new(table_name, [:named_table, :ordered_set, :public])
      History.Store.foldl(name, [], fn({key, _}, _) -> :ets.insert(table_name, {key, :ok}) end)
    end
    remove = if type == :automatic, do: round(limit * @table_limit_exceeded_factor) + current_size - limit, else: min(limit, current_size)
    Enum.reduce(0..remove, :ets.first(table_name),
      fn(_, key) ->
        :ets.delete(table_name, key)
        History.Store.delete_data(name, key)
        :ets.first(table_name)
      end)
  end

  defp save_and_find_history_x_identifiers(command, true) do
    if String.contains?(command, History.exec_name()),
       do: {false, find_history_x_identifiers(command)},
       else: {true, nil}
  end

  defp save_and_find_history_x_identifiers(command, _), do:
    {String.contains?(command, History.exec_name()), nil}

  defp find_history_x_identifiers(command) do
    tokens = string_to_tokens(command)
    {_, quoted} = Enum.reduce_while(tokens, [],
                    fn({:alias, _, :History} = history, acc) -> {:halt, [history | acc]};
                      (token, acc) -> {:cont, [token | acc]}
                    end)
                  |> Enum.reverse()
                  |> :elixir.tokens_to_quoted("", [])
    response = Macro.to_string(quoted) |> String.replace("History", "")
    if response == "", do: nil, else: response
  end

  defp string_to_tokens(command) do
    command = to_charlist(command)
    try do
      {{_, tokens}, _} = Code.eval_string(":elixir.string_to_tokens(#{inspect command},  1, \"\", [])")
      tokens
    catch
      _,_ ->
        {{_, tokens}, _} = Code.eval_string(":elixir.string_to_tokens(#{inspect command}, 1,  1, \"\", [])")
        tokens
    end
  end

  defp modify_command(command, shell_pid, process_info) do
    case Map.get(process_info, shell_pid) do
      nil ->
        command
      %{prepend_ids: prepend_ids} = _shell_config ->
        if prepend_ids == nil do
          command
        else
          if String.starts_with?(command, prepend_ids),
             do: command,
             else: "#{prepend_ids} #{command}"
        end
    end
  end

  defp de_alias_command(command, nil), do: command
  defp de_alias_command(command, alias), do: String.replace(command, alias, "History.")

end
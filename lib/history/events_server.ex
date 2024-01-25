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
  @moduledoc false
  
  @size_check_interval 60 * 1000
  @table_limit_exceeded_factor 0.1

  @history_buffer_size 75
  @save_immediate_buffer_duplicates false

  @history_scan_key  <<21>>     # ctrl+u
  @history_down_key <<11>>    # ctrl+k
  @editor_key <<22>>
  @enter_key "\r"
  
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
 def edit_command(command) do
  GenServer.cast(__MODULE__, {:edit_command, self(), command})
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
            History.Store.close_store(value.store_name)
        (_) -> :ok
      end)
      {:stop, :normal, :ok_done, process_info}
  end

  def handle_call(:get_state, _from, process_info) do
    new_process_info = Enum.map(process_info,
                         fn({pid, %{store_name: name} = map}) ->
                            {pid, %{map | size: History.Store.info(name, :size)}}
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
   process_info = paste_command(command, shell_pid, process_info)
    {:noreply, process_info}
  end

  def handle_cast({:edit_command, shell_pid, command}, process_info) do
    process_info = edit_command(command, shell_pid, process_info)
     {:noreply, process_info}
   end
   
  def handle_cast({:new_history_limit, new_value}, process_info) do
    new_process_info = %{process_info | limit: new_value}
    apply_table_limits(new_process_info)
    {:noreply, new_process_info}
  end

  def handle_cast({:key_buffer_history, true}, %{key_buffer_history: false, beam_node: beam_node} = process_info) do
    new_process_info =
      Enum.reduce(process_info, process_info,
              fn({shell_pid, shell_config}, process_info) when is_pid(shell_pid) ->
                    activity_queue = create_activity_queue(shell_config, true)
                    activity_pid = keystroke_activity_monitor(beam_node)
                    Map.put(process_info, shell_pid, %{shell_config | queue: activity_queue, keystroke_monitor_pid: activity_pid})
                (_, process_info) ->
                    process_info
              end)
    {:noreply, %{new_process_info | key_buffer_history: true}}
  end

  def handle_cast({:key_buffer_history, false}, %{key_buffer_history: true} = process_info) do
    new_process_info =
      Enum.reduce(process_info, process_info,
              fn({shell_pid, %{server_pid: server_pid, keystroke_monitor_pid: kbh_pid} = shell_config}, process_info) when is_pid(shell_pid) ->
                    if is_pid(kbh_pid),
                       do: send(kbh_pid, :exit),
                       else: :erlang.trace(server_pid, false, [:receive])
                    Map.put(process_info, shell_pid, %{shell_config | queue: {0, []}, keystroke_monitor_pid: nil})
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


  def handle_info({:trace, _, :send, {:eval, _, command, _, _}, shell_pid}, process_info) do
    case Map.get(process_info, shell_pid) do
      shell_config when is_map(shell_config) ->
        {:noreply, %{process_info | shell_pid => %{shell_config | pending_command: shell_config.pending_command <> command}}}
      _ ->
        {:noreply, process_info}
    end
  end

  def handle_info({:trace, _, :receive, {:evaled, shell_pid, :ok, _}}, process_info) do
    case validate_command(process_info, shell_pid) do
      {true, new_command, new_process_info} ->
        new_process_info = save_traced_command(new_command, shell_pid, new_process_info)
        {:noreply, new_process_info}

      {_, _, new_process_info} ->
        {:noreply, new_process_info}
    end
  end

  def handle_info({:trace, _, :receive, {:evaled, shell_pid, :error, _}}, process_info) do
    case Map.get(process_info, shell_pid) do
      shell_config when is_map(shell_config) ->
        {:noreply, %{process_info | shell_pid => %{shell_config | pending_command: ""}}}
      _ -> 
        {:noreply, process_info}  
      end
  end

  def handle_info({:trace, server_pid, :receive, {_, {:editor_data, data}}}, process_info) do
    Enum.find(process_info, 
                fn({k, v}) when is_pid(k) and is_map(v) -> v.server_pid == server_pid 
                  (_) -> false 
    end) 
    |> case do
      {_, %{server_pid: server_pid, shell_pid: shell_pid, user_driver_group: user_driver_group, user_driver: user_driver}} ->
        data = to_string(data)
        new_process_info = save_traced_command(data, shell_pid, process_info)
        snippet = String.slice(data, 0, 20) |> String.replace(~r/\s+/, " ")
        send(user_driver_group, {user_driver, {:data, "\n{:success, :history, #{inspect(snippet)}}\n"}}) 
        send(shell_pid, {:eval, server_pid, data, 1, {"", :other}})        
        {:noreply, new_process_info}
      
        _ -> 
        {:noreply, process_info}  
      end
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
  def handle_info({:scan_key, driver_pid}, %{key_buffer_history: true} = process_info) do
    new_process_info = cursor_action_handler(driver_pid, process_info, :up)
    {:noreply, new_process_info}
  end

  def handle_info({:down_key, driver_pid}, %{key_buffer_history: true} = process_info) do
    new_process_info = cursor_action_handler(driver_pid, process_info, :down)
    {:noreply, new_process_info}
  end

  def handle_info({:enter_key, driver_pid}, %{key_buffer_history: true} = process_info) do
    new_process_info = cursor_action_handler(driver_pid, process_info, :enter)
    {:noreply, new_process_info}
  end

  def handle_info({:editor_key, driver_pid}, %{key_buffer_history: true} = process_info) do
    new_process_info = cursor_action_handler(driver_pid, process_info, :editor)
    {:noreply, new_process_info}
  end
  
  def handle_info({:DOWN, _, :process, shell_pid, _}, %{scope: scope, store_count: store_count} = process_info) do
    case Map.get(process_info, shell_pid) do
      %{store_name: store_name, keystroke_monitor_pid: kbh_pid} ->
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

  defp do_register_new_shell(%{shell_pid: shell_pid,  server_pid: server_pid, beam_node: beam_node} = shell_config,
            %{key_buffer_history: key_buffer_history, scope: scope, store_count: store_count} = process_info) do
    if Map.get(process_info, shell_pid) == nil do
      store_count = History.Store.open_store(shell_config.store_name, shell_config.store_filename, scope, store_count)
      Node.monitor(shell_config.node, true)
      Process.monitor(shell_pid)
      activity_pid = keystroke_activity_monitor(beam_node)
      :erlang.trace(server_pid, true, [:send, :receive])
      activity_queue = create_activity_queue(shell_config, key_buffer_history)
      new_process_info = Map.put(process_info, shell_pid, %{shell_config | queue: activity_queue, keystroke_monitor_pid: activity_pid})
      new_process_info = Map.put(new_process_info, shell_config.node, shell_pid)
      %{new_process_info | store_count: store_count}
    else
      process_info
    end
  end

  
  defp keystroke_activity_monitor(remote_node) do
    dest = self()
    {mod, bin, _file} = :code.get_object_code(__MODULE__) 
    :rpc.call(remote_node, :code, :load_binary, [mod, :nofile, bin]) 
    Node.spawn(remote_node, 
        fn -> 
                 :erlang.trace(Process.whereis(:user_drv), true, [:send, :receive])
                 do_keystroke_activity_monitor(dest)
        end)              
  end
  
  defp do_keystroke_activity_monitor(dest) do
    receive do
       {_, pid, :receive, {_, {:data, @history_scan_key}}} -> 
          send(dest, {:scan_key, pid})
          do_keystroke_activity_monitor(dest)
          
        {_, pid, :receive, {_, {:data, @history_down_key}}} -> 
          send(dest, {:down_key, pid})
          do_keystroke_activity_monitor(dest)
          
        {_, pid, :receive, {_, {:data, @enter_key}}} -> 
          send(dest, {:enter_key, pid})
          do_keystroke_activity_monitor(dest)
          
       {_, pid, :receive, {_, {:data, @editor_key}}} -> 
          send(dest, {:editor_key, pid})
          do_keystroke_activity_monitor(dest)  
              
        _ ->
          do_keystroke_activity_monitor(dest)    
      end
  end

  defp create_activity_queue(%{store_name: store_name} = _shell_config, true) do
    current_size = History.Store.info(store_name, :size)
    if current_size > 0 do
      start = min(@history_buffer_size, current_size)
      {0, History.Events.do_get_history_registration(store_name, start * -1, current_size)}
    else
      {0, []}
    end
  end

  defp create_activity_queue(_shell_config, _), do:
    {0, []}
  
    defp send_to_shell(%{user_driver: user_driver, server_pid: user_driver_group}, command, :open_editor) do
      send(user_driver, {user_driver_group, {:open_editor, command}})
    end
    
  defp send_to_shell(%{user_driver: user_driver, user_driver_group: user_driver_group, last_scan_command: last_command}, command, :scan_action) do
    command = String.replace(command, ~r/\s+/, " ")
    send(user_driver, {user_driver_group, 
                {:requests, [{:move_rel, -String.length(last_command)}, :new_prompt, :delete_after_cursor,
                             {:insert_chars_over, :unicode, command}]}
    })
  end
  
  defp send_to_shell(%{user_driver: user_driver, user_driver_group: user_driver_group}, command, :clear_line) do
    send(user_driver, {user_driver_group,  {:requests, [{:move_rel, -String.length(command)}, :clear]}})
  end
  
  defp send_to_shell(%{user_driver: user_driver, user_driver_group: user_driver_group}, :move_line_up) do
    send(user_driver, {user_driver_group, {:requests, [{:move_line, -1}]}})
  end
  
  defp send_to_shell(%{user_driver: user_driver, user_driver_group: user_driver_group}, command) do
    send(user_driver_group, {user_driver, {:data, String.replace(command, ~r/\s+/, " ")}})
  end

  defp paste_command(command, shell_pid, process_info) do
    case Map.get(process_info, shell_pid) do
      %{user_driver: user_driver, user_driver_group: user_driver_group} = shell_config ->
        send(user_driver_group, {user_driver, {:data, String.replace(command, ~r/\s+/, " ")}})
        %{process_info | shell_pid => %{shell_config | paste_buffer: command}}
      _ ->
        process_info
    end
  end
  
  defp edit_command(command, shell_pid, process_info) do
    case Map.get(process_info, shell_pid) do
      shell_config when is_map(shell_config) ->        
        send_to_shell(shell_config, command, :open_editor)
        %{process_info | shell_pid => %{shell_config | paste_buffer: command}}
      _ ->
        process_info
    end
  end
  
  defp cursor_action_handler(driver_pid, process_info, operation) do
    case Enum.find(process_info, fn({k, v}) -> is_pid(k) && v.user_driver == driver_pid end) do
      {_, %{queue: {_sp, []}}} ->
        process_info
                 
      {shell_pid,  shell_config} ->
        handle_cursor_action(shell_pid, shell_config, process_info, operation) 
        
      _ ->
        process_info
    end
  end

  defp handle_cursor_action(_, %{last_scan_command: ""}, process_info, :enter) do
    process_info
  end
  
  defp handle_cursor_action(_, %{last_scan_command: "", paste_buffer: ""}, process_info, :enter) do
    process_info
  end
  
  defp handle_cursor_action(shell_pid, %{queue: {_, queue}, last_scan_command: command} = shell_config, process_info, :enter) when byte_size(command) > 0 do
    send_to_shell(shell_config, command)
    send_to_shell(shell_config, :move_line_up)
    %{process_info | shell_pid => %{shell_config | queue: {0, queue}, last_scan_command: "", last_direction: :none}}
  end
  
  defp handle_cursor_action(shell_pid, %{queue: {_, queue}, last_scan_command: command, paste_buffer: ""} = shell_config, process_info, :editor) do
    send_to_shell(shell_config, "", :scan_action)
    send_to_shell(shell_config, command, :open_editor)
    %{process_info | shell_pid => %{shell_config | queue: {0, queue}, last_scan_command: "", last_direction: :none}}
  end
  
  defp handle_cursor_action(shell_pid, %{queue: {_, queue}, paste_buffer: command} = shell_config, process_info, :editor) do
    send_to_shell(shell_config, "", :scan_action)
    send_to_shell(shell_config, command, :open_editor)
    %{process_info | shell_pid => %{shell_config | queue: {0, queue}, last_scan_command: "", last_direction: :none}}
  end
  
  defp handle_cursor_action(shell_pid, %{queue: {current_search_pos, queue}, last_direction: last_direction} = shell_config, process_info, operation) do
    queue_size = Enum.count(queue)
    get_search_position(current_search_pos, queue_size, last_direction, operation)
    |> do_handle_cursor_action(shell_config, operation)
    |> then(fn(new_shell_config) -> %{process_info | shell_pid => new_shell_config} end) 
  end

  
  defp do_handle_cursor_action(search_pos, %{queue: {_, queue}} = shell_config, :down) when search_pos > 0 do
     command = Enum.at(queue, search_pos)
     send_to_shell(shell_config, command, :scan_action)
     %{shell_config | queue: {search_pos, queue}, last_direction: :down, last_scan_command: command}    
  end
  
  defp do_handle_cursor_action(search_pos, %{queue: {_, queue}, last_direction: :none} = shell_config, :down) when search_pos == 0 do
    send_to_shell(shell_config, "", :scan_action)
    %{shell_config | queue: {search_pos, queue}, last_direction: :none, last_scan_command: ""} 
 end
 
  defp do_handle_cursor_action(search_pos, %{queue: {_, queue}} = shell_config, :down) when search_pos == 0 do
    command = Enum.at(queue, search_pos)
    send_to_shell(shell_config, command, :scan_action)
    %{shell_config | queue: {search_pos, queue}, last_direction: :none, last_scan_command: command} 
  end

  defp do_handle_cursor_action(search_pos, %{queue: {_, queue}} = shell_config, :up) do
    command = Enum.at(queue, search_pos)
    send_to_shell(shell_config, command, :scan_action)
    %{shell_config | queue: {search_pos, queue}, last_direction: :up, last_scan_command: command}    
  end

  defp get_search_position(_, _size, :none, :up), do: 0
  defp get_search_position(_, _size, :none, :down), do: 0

  defp get_search_position(0, _size, :up, :down), do: 0
  defp get_search_position(1, _size, :up, :down), do: 0
  defp get_search_position(current_value, _size, :up, :down), do: current_value - 1

  defp get_search_position(0, _size, :down, :up), do: 1
  defp get_search_position(current_value, _size, :down, :up), do: current_value + 1

  defp get_search_position(0, _size, _, :up), do: 1
  defp get_search_position(current_value, size, _, :up) when current_value >= size, do: current_value
  defp get_search_position(current_value, _size, _, :up), do: current_value + 1

  defp get_search_position(0, _size, _, :down), do: 0
  defp get_search_position(current_value, _size, _, :down), do: current_value - 1


  defp queue_insert(command, {_, []}), do:
    do_queue_insert(command, [])

  defp queue_insert(command, {_, queue}) do
    if @save_immediate_buffer_duplicates do
      do_queue_insert(command, queue)
    else
      if List.first(queue) != command,
         do: do_queue_insert(command, queue),
         else: {0, queue}
    end
  end

  defp do_queue_insert(command, queue) do
    size = Enum.count(queue)
    cond do
      String.contains?(command, "\n{:success, :history, ") ->
        {0, queue}
    
      size >= @history_buffer_size ->
        {0, [command | Enum.take(queue, size-1)]}
      
      true -> 
        {0, [command | queue]}
    end
  end

  defp validate_command(process_info, shell_pid) do
    case Map.get(process_info, shell_pid) do
      shell_config when is_map(shell_config) ->
        do_validate_command(shell_config, process_info, shell_pid)
      _ ->
        process_info
    end
  end

  defp do_validate_command(%{pending_command: command} = shell_config, process_info, shell_pid) do
    if command_valid?(command) do
      {true, command, %{process_info | shell_pid => %{shell_config | pending_command: ""}}}
    else
      {false, nil, %{process_info | shell_pid => %{shell_config | pending_command: ""}}}
    end
  end

  defp command_valid?(command) do
    try do
      test_command = find_invalid_comments(command)
      Code.format_string!(test_command)
      true
    catch
      _, _ -> false
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
                    fn({:alias, _, :History} = history, acc) -> {:halt, [history | acc]}
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
      _, _ ->
        {{_, tokens}, _} = Code.eval_string(":elixir.string_to_tokens(#{inspect command}, 1,  1, \"\", [])")
        tokens
    end
  end

  defp modify_command(command, shell_pid, process_info) do
    case Map.get(process_info, shell_pid) do
      %{prepend_ids: prepend_ids} when is_nil(prepend_ids) ->
        command
    
      %{prepend_ids: prepend_ids} ->
        if String.starts_with?(command, prepend_ids),
           do: command,
           else: "#{prepend_ids} #{command}"
 
      _ ->
        command
    end
  end

end

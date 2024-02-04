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

defmodule IExHistory2.Bindings do
  @moduledoc false

  use GenServer
  
  @ets_name "ets_history_bindings"
  @store_name "history_bindings"
  @bindings_check_interval 2500

  @doc false
  def initialize(:not_ok),
    do: :not_ok

  @doc false
  def initialize(%{scope: scope, save_bindings: save_bindings?} = config) do
    if save_bindings? do 
      IExHistory2.persistence_mode(scope) 
      |> do_initialize(config)
    end
  end

  def do_initialize(%{init: true}, config) do
    load_bindings(config)
    start_link(config)
  end

  @doc false
  def do_initialize(_, _),
    do: :not_ok

  @doc false
  def get_binding_server_config(scope, save_bindings) do
    %{binding_count: 0,
      shell_pid: self(),
      scope: scope,
      server_pid: :group.whereis_shell(), 
      group_leader_pid: Process.group_leader(),
      registered_name: get_registered_name(),
      save_bindings: save_bindings,
      db_labels: init_stores(scope)
    }
  end 
   
   @doc false
   def start_link(%{registered_name: name} = config) do
    GenServer.start_link(__MODULE__, [config], name: name)
  end
  
   @doc false
   def display_bindings() do
    try do
      import IExHistory2.Events, only: [color: 1]
      get_bindings()
      |> Enum.sort()
      |> Enum.each(fn({name, val}) -> 
              val = pretty_print_binding(val, name)  
              IO.puts("\n#{IO.ANSI.white()}Binding: #{color(:binding)}#{name}")
              IO.puts("#{IO.ANSI.white()}Value:   #{val}")
      end)
      count = :ets.info(Process.get(:history_bindings_ets_label), :size)
      IO.puts("\nTotal: #{count} variables")
    catch
      _, _ -> []
    end
  end
  
  @doc false
  def get_bindings() do
    try do
      :ets.tab2list(Process.get(:history_bindings_ets_label))
    catch
      _, _ -> []
    end
  end

  @doc false
  def get_bindings(pid) do
    try do
      {_, dict} = Process.info(pid, :dictionary)
      :ets.tab2list(Keyword.get(dict, :history_bindings_ets_label))
    catch
      _, _ -> []
    end
  end
    
  @doc false
  def get_binding(var) do
    case :ets.lookup(Process.get(:history_bindings_ets_label), var) do
      [{_, val}] -> val
      _ -> raise("not found")
    end
  end

  @doc false
  def get_binding_as_string(var, name) do
    case get_binding(var, name, false) do
      ^var -> var
      res when is_bitstring(res) -> res
      res -> inspect(res, limit: :infinity, printable_limit: :infinity)
    end  
  end
    
  @doc false
  def get_binding(var, name, raise? \\ true)
  
  def get_binding(var, name, raise?) when is_bitstring(var) do
    String.trim(var)
    |> String.to_atom()
    |> get_binding(name, raise?)
  end
  
  def get_binding(var, name, raise?) do
    pid = if is_atom(name), 
      do: Process.whereis(name),
      else: name
    {_, dict} = Process.info(pid, :dictionary)
    case :ets.lookup(Keyword.get(dict, :history_bindings_ets_label), var) do
      [{_, val}] -> val
      _ when raise? -> raise("not found")
      _ -> var
    end
  end
  
  @doc false
  def get_value(label, ets_name) do
    case :ets.lookup(ets_name, label) do
      [{_, value}] -> value
      _ -> nil
    end
  end

  @doc false
  def unbind(vars) do
    save_bindings? = IExHistory2.configuration(:save_bindings, true)

    if save_bindings? do
      GenServer.call(get_registered_name(), {:unbind, vars})
      set_bindings_for_shell()
      :ok
    else
      :bindings_disabled
    end
  end

  @doc false
  def clear() do
    save_bindings? = IExHistory2.configuration(:save_bindings, true)

    if save_bindings? do
      GenServer.call(get_registered_name(), :clear)
      clear_bindings_from_shell()
    else
      :bindings_disabled
    end
  end

  @doc false
  def stop_clear() do
    save_bindings? = IExHistory2.configuration(:save_bindings, true)

    if save_bindings? do
      GenServer.call(get_registered_name(), :stop_clear)
      clear_bindings_from_shell()
    else
      :bindings_disabled
    end
  end

  @doc false
  def state(pretty \\ false) do
    save_bindings? = IExHistory2.configuration(:save_bindings, true)

    if save_bindings? do
      {_, rsp} = GenServer.call(get_registered_name(), :state)
      string = "#{IO.ANSI.white()}Current bindings are #{IO.ANSI.red()}#{rsp.binding_count}#{IO.ANSI.white()} variables in size"
      if pretty, do: IO.puts("#{string}"), else: string
    else
      string = "Bindings are not been saved."
      if pretty, do: IO.puts("#{string}"), else: string
    end
  end

  @doc false
  def raw_state() do
    save_bindings? = IExHistory2.configuration(:save_bindings, true)

    if save_bindings? do
      GenServer.call(get_registered_name(), :state)
    else
      :bindings_disabled
    end
  end

  @doc false
  def inject_command(command, name \\ nil)
  
  def inject_command(command, nil) do
    server = find_server()
    send(self(), {:eval, server, command, 1, {"", :other}})
  end
  
  def inject_command(command, name) do
    server = find_server(name)
    send(Process.whereis(name), {:eval, server, command, 1, {"", :other}})
  end
  
  @doc false
  def inject_command(command, pid, server) do
    send(pid, {:eval, server, command, 1, {"", :other}})
  end
  
  @doc false
  def find_server(),
    do: :group.whereis_shell()

  @doc false
  def find_server(name) do
    {_, dict} = Process.info(Process.whereis(name), :dictionary)
    Keyword.get(dict, :iex_server)
  end
  
  @doc false
  def get_registered_name() do
    gl_node = IExHistory2.my_real_node() |> Atom.to_string()
    String.to_atom("history_binding_finder_#{gl_node}")
  end

  
  @doc false
  def init([%{server_pid: server_pid, shell_pid: shell_pid} = config]) do
    Process.monitor(server_pid)
    Process.monitor(shell_pid)
    Process.send_after(self(), :check_bindings, @bindings_check_interval)
    {:ok, config}
  end

  def handle_call(:state, _from, %{db_labels: db_labels} = config) do
    size = :ets.info(db_labels.ets_name, :size)
    new_config =  %{config | binding_count: size}
    {:reply, {:state, new_config}, new_config}
  end 
  
  def handle_call(:clear, _from, %{db_labels: db_labels} = config) do      
    :ets.delete_all_objects(db_labels.ets_name)
    IExHistory2.Store.delete_all_objects(db_labels.store_name)
    size = :ets.info(config.db_labels.ets_name, :size)
    {:reply, :ok, %{config | binding_count: size}}
  end
  
  def handle_call({:unbind, vars}, _from, %{db_labels: db_labels} = config) do      
    Enum.each(vars, fn label ->
      :ets.delete(db_labels.ets_name, label)
      IExHistory2.Store.delete_data(db_labels.store_name, label)
    end)
    size = :ets.info(config.db_labels.ets_name, :size)
    {:reply, :ok, %{config | binding_count: size}}
  end
  
  def handle_call(:stop_clear, _from, %{db_labels: db_labels} = config) do      
    :ets.delete_all_objects(db_labels.ets_name)
    IExHistory2.Store.delete_all_objects(db_labels.store_name)
    IExHistory2.Store.close_store(db_labels.store_name)
    {:stop, :normal, :ok, config}
  end
    
  def handle_call(_msg, _from, config) do      
    {:reply, :ok, config}
  end
  
  def handle_cast(_msg, config) do      
    {:noreply, config}
  end
  
  def handle_info(:check_bindings, %{db_labels: db_labels} = config) do 
    new_bindings = get_bindings_from_shell(config)
    persist_bindings(new_bindings, db_labels)
    Process.send_after(self(), :check_bindings, @bindings_check_interval)     
    {:noreply, config}
  end
  
  def handle_info({:DOWN, _ref, :process, _object, _reason}, config) do      
    {:stop, :normal, config}
  end
  
  def handle_info(_msg, config) do      
    {:noreply, config}
  end
    
  defp init_stores(scope) do
    my_node = IExHistory2.my_real_node()
    str_label = "#{scope}_#{my_node}"

    ets_name = String.to_atom("#{@ets_name}_#{str_label}")
    store_name = String.to_atom("#{@store_name}_#{str_label}")
    store_filename = to_charlist("#{IExHistory2.get_log_path()}/bindings_#{str_label}.dat")
    Process.put(:history_bindings_ets_label, ets_name)

    if :ets.info(ets_name) == :undefined do
      :ets.new(ets_name, [:named_table, :public])
      :ets.give_away(ets_name, :erlang.whereis(:init), [])
    end

    IExHistory2.Store.open_store(store_name, store_filename, scope)

    %{ets_name: ets_name, store_name: store_name, store_filename: store_filename}
  end

  defp persist_bindings([], _), do: :ok

  defp persist_bindings(bindings, %{ets_name: ets_name, store_name: store_name}) do
    Enum.map(bindings, fn {label, value} ->
      case :ets.lookup(ets_name, label) do
        _ when value == :could_not_bind ->
          :ets.delete(ets_name, label)
          IExHistory2.Store.delete_data(store_name, label)

        [{_, ^value}] ->
          :ok

        _ ->
          :ets.insert(ets_name, {label, value})
          IExHistory2.Store.save_data(store_name, {label, value})
      end
    end)
  end

  defp get_bindings_from_shell(%{shell_pid: shell_pid, server_pid: server_pid} = _config) do
    variables =
      IEx.Evaluator.variables_from_binding(shell_pid, server_pid, "")
      |> Enum.map(&String.to_atom(&1))

    bindings =
      for var <- variables do
        try do
          elem(IEx.Evaluator.value_from_binding(shell_pid, server_pid, var, %{}), 1)
        catch
          _, _ -> :could_not_bind
        end
      end

    Enum.zip(variables, bindings)
  end

  defp load_bindings(%{shell_pid: shell_pid, server_pid: server_pid, db_labels: %{ets_name: ets_name, store_name: store_name}}) do
    bindings =
      IExHistory2.Store.foldl(store_name, [], fn {label, value}, acc ->
        :ets.insert(ets_name, {label, value})
        ["#{label} = IExHistory2.Bindings.get_value(:#{label},:#{ets_name}); " | acc]
      end)
      |> List.to_string()

    inject_command(bindings <> " :ok", shell_pid, server_pid)
  end

  defp clear_bindings_from_shell() do
    inject_command("IEx.Evaluator.init(:ack, :group.whereis_shell(), Process.group_leader(), 0, [binding: []])")
  end

  defp set_bindings_for_shell() do
    ets_name = Process.get(:history_bindings_ets_label)
    clear_bindings_from_shell()

    bindings =
      :ets.foldl(
        fn {label, _value}, acc ->
          ["#{label} = IExHistory2.Bindings.get_value(:#{label},:#{ets_name}); " | acc]
        end,
        [],
        ets_name
      )
      |> List.to_string()

    inject_command(bindings <> " :ok")
  end
  
  defp pretty_print_binding(value, name) when is_function(value) do
    case IExHistory2.Events.find_history_item("#{name}=") do
      {:ok, val} -> 
        String.split(val, "=", parts: 2) 
        |> List.last() 
        |> String.trim()
        |> then(fn v -> {:func, v} end)
        |> pretty_print_binding(name)
        
      _ -> pretty_print_binding({:func, value}, name) 
    end
  end

  defp pretty_print_binding(value, _) do
    String.slice(inspect(value, syntax_colors: IO.ANSI.syntax_colors, pretty: false, limit: 50), 0, 150)
  end
  
end

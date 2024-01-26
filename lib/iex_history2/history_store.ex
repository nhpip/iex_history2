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

defmodule IExHistory2.Store do
  @moduledoc false

  @doc false
  def open_store(name, filename, scope, store_count \\ 0) do
    if scope in [:local, :node] do
      :dets.open_file(name, [{:file, to_charlist(filename)}])
      store_count + 1
    else
      if store_count == 0 do
        :dets.open_file(name, [{:file, to_charlist(filename)}])
        store_count + 1
      else
        store_count
      end
    end
  end

  @doc false
  def close_store(name, scope \\ :local, store_count \\ 0) do
    if scope in [:local, :node] do
      :dets.close(name)
      store_count - 1
    else
      if store_count == 1 do
        :dets.close(name)
        store_count - 1
      else
        0
      end
    end
  end

  @doc false
  def save_data(name, data) do
    :dets.insert(name, data)
    :dets.sync(name)
  end

  @doc false
  def delete_data(name, key) do
    :dets.delete(name, key)
  end

  @doc false
  def delete_all_objects(name), do: :dets.delete_all_objects(name)

  @doc false
  def info(name), do: :dets.info(name)

  @doc false
  def info(name, what), do: :dets.info(name, what)

  @doc false
  def get_all_objects(name), do: :dets.foldl(fn event, acc -> [event | acc] end, [], name)

  @doc false
  def foldl(name, init, fun) do
    :dets.foldl(fun, init, name)
  end
end

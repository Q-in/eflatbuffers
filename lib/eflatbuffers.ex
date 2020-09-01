defmodule Eflatbuffers do

  def parse_schema(schema_str) do
    Eflatbuffers.Schema.parse(schema_str)
  end

  def parse_schema!(schema_str) do
    case parse_schema(schema_str) do
      {:ok, schema}   -> schema
      error           -> throw error
    end
  end

  def write!(map, schema_str) when is_binary(schema_str) do
    write!(map, parse_schema!(schema_str))
  end


 def write!(map, {_, %{root_type: root_type} = options} = schema) do
    root_table = [<< vtable_offset :: little-size(16) >> | _] = Eflatbuffers.Writer.write({:table, %{ name: root_type }}, map, [], schema)
    root_table = :erlang.iolist_to_binary root_table

    aling_to_4 = case rem(byte_size(root_table), 4) do
      0 -> ""
      x -> :binary.copy <<0>>, x
    end

    file_identifier =
      case Map.get(options, :file_identifier) do
        :skip                 -> <<>>
        << bin :: size(32) >> -> << bin :: size(32) >>
        _                     -> << 0, 0, 0, 0 >>
      end

    vtable_ptr_updated = vtable_offset + 4 + byte_size(file_identifier) + byte_size(aling_to_4)
    [<< vtable_ptr_updated :: little-size(32) >>, file_identifier, aling_to_4, root_table]
    |> :erlang.iolist_to_binary
  end

  def write(map, schema_str) when is_binary(schema_str) do
    case parse_schema(schema_str) do
      {:ok, schema} -> write(map, schema)
      error         -> error
    end
  end

  def write(map, schema) do
    try do
      {:ok, write!(map, schema)}
    catch
      error -> error
    rescue
      error -> {:error, error}
    end
  end

  def read!(data, schema_str) when is_binary(schema_str) do
    read!(data, parse_schema!(schema_str))
  end

  def read!(data, {_, schema_options = %{root_type: root_type}} = schema) do
    match_identifiers(data, schema_options)
    Eflatbuffers.Reader.read({:table, %{ name: root_type }}, 0, data, schema)
  end

  def match_identifiers( << _::size(4)-binary, identifier_data::size(4)-binary, _::binary >>, schema_options) do
    case Map.get(schema_options, :file_identifier) do
      # nothing in schema
      nil                -> :ok
      # schema matches data
      ^identifier_data   -> :ok
      # defined in schema but data says something else
      identifier_schema  -> throw({:error, {:identifier_mismatch, %{data: identifier_data, schema: identifier_schema}}})
    end
  end

  def read(data, schema_str) when is_binary(schema_str) do
    case parse_schema(schema_str) do
      {:ok, schema} -> read(data, schema)
      error         -> error
    end
  end

  def read(data, schema) do
    try do
      {:ok, read!(data, schema)}
    catch
      error -> error
    rescue
      error -> {:error, error}
    end
  end

  def get(data, path, schema) do
    try do
      {:ok, get!(data, path, schema)}
    catch
      error -> error
    rescue
      error -> {:error, error}
    end
  end

  def get!(data, path, schema) when is_binary(schema) do
    get!(data, path, parse_schema!(schema))
  end
  def get!(data, path, {_tables, %{root_type: root_type}} = schema) do
    Eflatbuffers.RandomAccess.get(path, {:table, %{ name: root_type }}, 0, data, schema)
  end


end

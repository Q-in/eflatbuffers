defmodule EflatbuffersTest do
  use ExUnit.Case
  import TestHelpers
  doctest Eflatbuffers

  def before_test do
    flush_port_commands()
  end

  test "test enum" do
    schema = """
    enum EHitResult : byte { Miss = 1, None, Hit, Critical, Count }

    table FBAttackAck {
        type:ushort;
        order:bool;
        encode:bool;
        OffenseUnique:uint;
        DefenseUnique:uint;
        PosX:float;
        PosY:float;
        PosZ:float;
        EHitResult:EHitResult;
        WeaponNo:int;
        IsObstacle:bool;
        ToPosX:float;
        ToPosY:float;
        ToPosZ:float;
        IsDie:bool;
    }
    root_type FBAttackAck;
    """

    schema = Eflatbuffers.Schema.parse!(schema)

    IO.inspect schema 

    IO.puts("""
        00000000  4a 00 00 00 c9 36 24 00  00 00 20 00 20 00 00 00  J....6$... . ...
        00000010  00 00 00 00 04 00 08 00  0c 00 00 00 10 00 00 00  ................
        00000020  14 00 00 00 18 00 00 00  1c 00 20 00 00 00 36 0b  .......... ...6.
        00000030  00 12 5a cc 11 1a d8 1d  14 44 58 a5 6a 43 38 38  ..Z......DX.jC88
        00000040  03 00 88 36 13 44 ec 0e  6b 43                    ...6.D..kC
    """)

    real =
      Base.decode16!(
        "2400000020002000000000000000040008000c0000001000000014000000180000001c0020000000360b00125acc111ad81d144458a56a433838030088361344ec0e6b43",
        case: :lower
      )

    IO.inspect Eflatbuffers.read!(real, schema)
  end

  test "creating test data" do
    expected = <<12, 0, 0, 0, 8, 0, 8, 0, 6, 0, 0, 0, 8, 0, 0, 0, 0, 0, 17, 0>>
    assert expected == reference_fb(:simple_table, %{field_a: 17})
  end

  ### complete flatbuffer binaries

  test "table of scalars" do
    map = %{
      my_byte: 66,
      my_ubyte: 200,
      my_bool: true,
      my_short: -23,
      my_ushort: 42,
      my_int: -1000,
      my_uint: 1000,
      my_float: 3.124,
      my_long: -10_000_000,
      my_ulong: 10_000_000,
      my_double: 3.141593
    }

    assert_full_circle(:all_my_scalars, map)
  end

  test "table of scalars with defaults" do
    map = %{
      my_byte: -7,
      my_ubyte: 7,
      my_bool: true,
      my_short: -7,
      my_ushort: 7,
      my_int: -7,
      my_uint: 7,
      my_float: -7,
      my_long: -7,
      my_ulong: 7,
      my_double: -7
    }

    assert_full_circle(:defaults, map)
  end

  test "read simple table" do
    map = %{
      field_a: 42,
      field_b: 23
    }

    assert_full_circle(:simple_table, map)
  end

  test "read simple table with extended schema" do
    map = %{
      field_a: 42,
      field_b: 23
    }

    assert_full_circle(:simple_table_plus, :simple_table, map)
  end

  test "read table with missing values" do
    map = %{}
    assert_full_circle(:simple_table, map)
  end

  test "table with scalar vector" do
    map = %{
      int_vector: [23, 42, 666]
    }

    assert_full_circle(:int_vector, map)
  end

  test "table with string vector" do
    map = %{
      string_vector: ["foo", "bar", "baz"]
    }

    assert_full_circle(:string_vector, map)
  end

  test "table with enum" do
    map = %{
      enum_field: "Green"
    }

    assert_full_circle(:enum_field, map)
    assert_full_circle(:enum_field, %{})
  end

  test "vector of enum" do
    map = %{
      enum_fields: ["Blue", "Green", "Red"]
    }

    # writing
    {:ok, reply} = Eflatbuffers.write(map, load_schema(:vector_of_enums))
    assert(map == Eflatbuffers.read!(reply, load_schema(:vector_of_enums)))
  end

  test "table with union" do
    map = %{
      data: %{greeting: 42},
      data_type: "bye",
      additions_value: 123
    }

    assert_full_circle(:union_field, map)
  end

  test "table with table vector" do
    map = %{
      inner: [%{value_inner: "aaa"}]
    }

    assert_full_circle(:table_vector, map)
  end

  # test "nested vectors (not supported by flatc)" do
  #  map = %{
  #    the_vector: [[1,2,3],[4,5,6]],
  #  }
  #  # writing
  #  {:ok, reply} = Eflatbuffers.write(map, load_schema(:nested_vector))
  #  assert(map == Eflatbuffers.read!(reply, load_schema(:nested_vector)))
  # end

  test "fb with string" do
    map = %{
      my_string: "hello",
      my_bool: true
    }

    assert_full_circle(:string_table, map)
  end

  test "config debug fb" do
    map = %{technologies: [%{category: "aaa"}, %{}]}
    assert_full_circle(:config_path, map)
  end

  test "config fb" do
    {:ok, schema} = Eflatbuffers.Schema.parse(load_schema({:doge, :config}))
    map = Poison.decode!(File.read!("test/complex_schemas/config.json"), keys: :atoms)
    # writing
    reply = Eflatbuffers.write!(map, schema)
    reply_map = Eflatbuffers.read!(reply, schema)
    assert [] == compare_with_defaults(round_floats(map), round_floats(reply_map), schema)

    assert_full_circle({:doge, :config}, map)
  end

  test "commands fb" do
    maps = [
      %{data_type: "RefineryStartedCommand", data: %{}},
      %{data_type: "CraftingFinishedCommand", data: %{}},
      %{data_type: "MoveBuildingCommand", data: %{from: %{x: 23, y: 11}, to: %{x: 42, y: -1}}}
    ]

    Enum.each(
      maps,
      fn map -> assert_full_circle({:doge, :commands}, map) end
    )
  end

  test "read nested table" do
    map = %{
      value_outer: 42,
      inner: %{value_inner: 23}
    }

    assert_full_circle(:nested, map)
  end

  test "write fb" do
    map = %{my_bool: true, my_string: "max", my_second_string: "minimum"}
    assert_full_circle(:table_bool_string_string, map)
  end

  test "no file identifier" do
    fb = Eflatbuffers.write!(%{}, load_schema(:no_identifier))
    assert <<_::size(4)-binary>> <> <<0, 0, 0, 0>> <> <<_::binary>> = fb
  end

  test "file identifier" do
    fb_id = Eflatbuffers.write!(%{}, load_schema(:identifier))
    fb_no_id = Eflatbuffers.write!(%{}, load_schema(:no_identifier))
    assert <<_::size(32)>> <> "helo" <> <<_::binary>> = fb_id
    assert <<_::size(32)>> <> <<0, 0, 0, 0>> <> <<_::binary>> = fb_no_id
    assert %{} == Eflatbuffers.read!(fb_id, load_schema(:no_identifier))

    assert {:error, {:identifier_mismatch, %{data: <<0, 0, 0, 0>>, schema: "helo"}}} ==
             catch_throw(Eflatbuffers.read!(fb_no_id, load_schema(:identifier)))

    assert_full_circle(:identifier, %{})
    assert_full_circle(:no_identifier, %{})
  end

  test "path errors" do
    map = %{foo: true, tables_field: [%{string_field: "hello"}]}
    assert_full_circle(:error, map)

    map = %{foo: true, tables_field: [%{}, %{bar: 3, string_field: 23}]}

    assert {:error, {:wrong_type, :string, 23, [{:tables_field}, [1], {:string_field}]}} ==
             catch_throw(
               Eflatbuffers.write!(map, Eflatbuffers.parse_schema!(load_schema(:error)))
             )

    map = %{foo: true, tables_field: [%{}, "hoho!"]}

    assert {:error, {:wrong_type, :table, "hoho!", [{:tables_field}, [1]]}} ==
             catch_throw(
               Eflatbuffers.write!(map, Eflatbuffers.parse_schema!(load_schema(:error)))
             )

    map = %{foo: true, tables_field: 123}

    assert {:error, {:wrong_type, :vector, 123, [{:tables_field}]}} ==
             catch_throw(
               Eflatbuffers.write!(map, Eflatbuffers.parse_schema!(load_schema(:error)))
             )
  end
end

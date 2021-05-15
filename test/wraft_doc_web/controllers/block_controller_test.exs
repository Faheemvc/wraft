defmodule WraftDocWeb.Api.V1.BlockControllerTest do
  use WraftDocWeb.ConnCase
  import WraftDoc.Factory

  alias WraftDoc.{Document.Block, Repo}

  @data [
    %{"label" => "January", "value" => 10},
    %{"label" => "February", "value" => 20},
    %{"label" => "March", "value" => 5},
    %{"label" => "April", "value" => 60},
    %{"label" => "May", "value" => 80},
    %{"label" => "June", "value" => 70},
    %{"label" => "Julay", "value" => 90}
  ]
  @update_valid_attrs %{
    "btype" => "pie",
    "file_url" => "/usr/local/hoem/filex.svg",
    "dataset" => %{
      "backgroundColor" => "transparent",
      "data" => @data,
      "format" => "svg",
      "height" => 512,
      "type" => "pie",
      "width" => 512
    },
    "endpoint" => "blocks_api",
    "name" => "Farming"
  }
  @invalid_attrs %{
    name: "energy consumption",
    btype: "pie",
    endpoint: "quick_chart"
  }
  setup %{conn: conn} do
    user = insert(:user)

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> post(
        Routes.v1_user_path(conn, :signin, %{
          email: user.email,
          password: user.password
        })
      )

    conn = assign(conn, :current_user, user)
    # Open bypass connection
    bypass = Bypass.open()

    {:ok, %{conn: conn, bypass: bypass}}
  end

  test "create block renders error.json for invalid attributes", %{conn: conn} do
    user = conn.assigns[:current_user]
    insert(:membership, organisation: user.organisation)

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{conn.assigns.token}")
      |> assign(:current_user, user)

    conn = post(conn, Routes.v1_block_path(conn, :create, @invalid_attrs))
    assert json_response(conn, 400)["status"] == false
    assert json_response(conn, 400)["message"] == "invalid endpoint"
  end

  test "update blocks and render update.json for valid attributes", %{conn: conn, bypass: bypass} do
    Bypass.expect(bypass, fn conn ->
      Plug.Conn.resp(conn, 200, "{\"url\":\"/test.jpg\"}")
    end)

    params = Map.put(@update_valid_attrs, "api_route", "http://localhost:#{bypass.port}")
    user = conn.assigns.current_user
    insert(:membership, organisation: user.organisation)

    block = insert(:block, creator: user, organisation: user.organisation)

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{conn.assigns.token}")
      |> assign(:current_user, conn.assigns.current_user)

    count_before = Block |> Repo.all() |> length()
    conn = put(conn, Routes.v1_block_path(conn, :update, block.id), params)

    assert json_response(conn, 200)["name"] == @update_valid_attrs["name"]
    count_after = Block |> Repo.all() |> length()
    assert count_before == count_after
  end

  test "does not update blocks for invalid attributes", %{conn: conn} do
    user = conn.assigns.current_user
    insert(:membership, organisation: user.organisation)
    block = insert(:block, creator: user, organisation: user.organisation)

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{conn.assigns.token}")
      |> assign(:current_user, conn.assigns.current_user)

    conn = put(conn, Routes.v1_block_path(conn, :update, block.id), @invalid_attrs)
    assert json_response(conn, 400)["message"] == "invalid endpoint"
  end

  test "renders show.json on existing id", %{conn: conn} do
    user = conn.assigns.current_user
    insert(:membership, organisation: user.organisation)

    block = insert(:block, creator: user, organisation: user.organisation)

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{conn.assigns.token}")
      |> assign(:current_user, conn.assigns.current_user)

    conn = get(conn, Routes.v1_block_path(conn, :show, block.id))
    assert json_response(conn, 200)["name"] == block.name
  end

  test "renders error not found id doesnot exist", %{conn: conn} do
    user = conn.assigns[:current_user]
    insert(:membership, organisation: user.organisation)

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{conn.assigns.token}")
      |> assign(:current_user, user)

    conn = get(conn, Routes.v1_block_path(conn, :show, Ecto.UUID.autogenerate()))
    assert json_response(conn, 400)["errors"] == "The Block id does not exist..!"
  end

  test "deletes the block and renders the block.json", %{conn: conn} do
    user = conn.assigns.current_user
    insert(:membership, organisation: user.organisation)
    block = insert(:block, creator: user, organisation: user.organisation)

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{conn.assigns.token}")
      |> assign(:current_user, conn.assigns.current_user)

    count_before = Block |> Repo.all() |> length()
    conn = delete(conn, Routes.v1_block_path(conn, :delete, block.id))
    count_after = Block |> Repo.all() |> length()
    assert json_response(conn, 200)["name"] == block.name
    assert count_before - 1 == count_after
  end

  test "error not found on user from another organisation", %{conn: conn} do
    user = conn.assigns[:current_user]
    insert(:membership, organisation: user.organisation)
    block = insert(:block)

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{conn.assigns.token}")
      |> assign(:current_user, user)

    conn = get(conn, Routes.v1_block_path(conn, :show, block.id))
    assert json_response(conn, 400)["errors"] == "The Block id does not exist..!"
  end
end

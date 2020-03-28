defmodule WraftDocWeb.Api.V1.BlockController do
  use WraftDocWeb, :controller

  use PhoenixSwagger

  alias WraftDoc.{Document, Document.Block}
  action_fallback(WraftDocWeb.FallbackController)

  def swagger_defnitions do
    %{
      BlockRequest:
        swagger_schema do
          title("Block Request")
          description("A block to Be created to add to instances")

          properties do
            name(:string, "Block name", required: true)
            btype(:string, "Block type", required: true)
            dataset(:map, "Dataset for creating charts", required: true)
          end

          example(%{
            name: "Energy consumption",
            btype: "pie",
            dataset:
              "{type:'pie',data:{labels:['January','February', 'March','April', 'May'], datasets:[{data:[50,60,70,180,190]}]}}"
          })
        end,
      Block:
        swagger_schema do
          title("Block")
          description("A Block")

          properties do
            name(:string, "Block name", required: true)
            btype(:string, "Block type", required: true)
            dataset(:map, "Dataset for creating charts", required: true)
            inserted_at(:string, "When was the user inserted", format: "ISO-8601")
            updated_at(:string, "When was the user last updated", format: "ISO-8601")
          end

          example(%{
            name: "Energy consumption",
            btype: "pie",
            dataset: %{
              type: "pie",
              data: %{
                labels: ["January", "February", "March", "April", "May"],
                datasets: [%{data: [50, 60, 70, 180, 190]}]
              }
            },
            updated_at: "2020-01-21T14:00:00Z",
            inserted_at: "2020-02-21T14:00:00Z"
          })
        end
    }
  end

  @doc """
  Create New one
  """
  swagger_path :create do
    post("/block")
    summary("Register Block")
    description("Create a block")
    operation_id("create_block")
    tag("Block")

    parameters do
      block(:block, Schema.ref(:BlockRequest), "Block to Create", required: true)
    end

    response(201, "Created", Schema.ref(:Organisation))
    response(422, "Unprocessable Entity", Schema.ref(:Error))
    response(401, "Unauthorized", Schema.ref(:Error))
  end

  @spec create(Plug.Conn.t(), map) :: Plug.Conn.t()
  def create(conn, params) do
    current_user = conn.assigns.current_user

    with %Block{} = block <- Document.create_block(current_user, params) do
      chart = Document.create_chart(params["dataset"])

      conn
      |> put_status(:created)
      |> render("block.json", block: block)
    end
  end
end

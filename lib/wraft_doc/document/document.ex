defmodule WraftDoc.Document do
  @moduledoc """
  Module that handles the repo connections of the document context.
  """
  import Ecto
  import Ecto.Query

  alias WraftDoc.{
    Repo,
    Account.User,
    Document.Layout,
    Document.ContentType,
    Document.Engine,
    Document.Instance,
    Document.Instance.History,
    Document.Theme,
    Document.DataTemplate,
    Document.Asset,
    Document.LayoutAsset,
    Document.FieldType,
    Document.ContentTypeField,
    Document.Counter,
    Enterprise,
    Enterprise.Flow,
    Enterprise.Flow.State,
    Document.Block
  }

  alias WraftDocWeb.AssetUploader

  @doc """
  Create a layout.
  """
  @spec create_layout(User.t(), Engine.t(), map) :: Layout.t() | {:error, Ecto.Changeset.t()}
  def create_layout(%{organisation_id: org_id} = current_user, engine, params) do
    params = params |> Map.merge(%{"organisation_id" => org_id})

    current_user
    |> build_assoc(:layouts, engine: engine)
    |> Layout.changeset(params)
    |> Spur.insert()
    |> case do
      {:ok, layout} ->
        layout = layout |> layout_files_upload(params)
        layout |> fetch_and_associcate_assets(current_user, params)
        layout |> Repo.preload([:engine, :creator, :assets])

      changeset = {:error, _} ->
        changeset
    end
  end

  @doc """
  Upload layout slug file.
  """
  @spec layout_files_upload(Layout.t(), map) :: Layout.t() | {:error, Ecto.Changeset.t()}
  def layout_files_upload(layout, %{"slug_file" => _} = params) do
    layout_update_files(layout, params)
  end

  def layout_files_upload(layout, %{"screenshot" => _} = params) do
    layout_update_files(layout, params)
  end

  def layout_files_upload(layout, _params) do
    layout |> Repo.preload([:engine, :creator])
  end

  # Update the layout on fileupload.
  @spec layout_update_files(Layout.t(), map) :: Layout.t() | {:error, Ecto.Changeset.t()}
  defp layout_update_files(layout, params) do
    layout
    |> Layout.file_changeset(params)
    |> Repo.update()
    |> case do
      {:ok, layout} ->
        layout

      {:error, _} = changeset ->
        changeset
    end
  end

  # Get all the assets from their UUIDs and associate them with the given layout.
  defp fetch_and_associcate_assets(layout, current_user, %{"assets" => assets}) do
    (assets || "")
    |> String.split(",")
    |> Stream.map(fn x -> get_asset(x) end)
    |> Stream.map(fn x -> associate_layout_and_asset(layout, current_user, x) end)
    |> Enum.to_list()
  end

  defp fetch_and_associcate_assets(_layout, _current_user, _params), do: nil

  # Associate the asset with the given layout, ie; insert a LayoutAsset entry.
  defp associate_layout_and_asset(_layout, _current_user, nil), do: nil

  defp associate_layout_and_asset(layout, current_user, asset) do
    layout
    |> build_assoc(:layout_assets, asset: asset, creator: current_user)
    |> LayoutAsset.changeset()
    |> Repo.insert()
  end

  @doc """
  Create a content type.
  """
  @spec create_content_type(User.t(), Layout.t(), Flow.t(), map) ::
          ContentType.t() | {:error, Ecto.Changeset.t()}
  def create_content_type(%{organisation_id: org_id} = current_user, layout, flow, params) do
    params = params |> Map.merge(%{"organisation_id" => org_id})

    current_user
    |> build_assoc(:content_types, layout: layout, flow: flow)
    |> ContentType.changeset(params)
    |> Spur.insert()
    |> case do
      {:ok, %ContentType{} = content_type} ->
        content_type |> fetch_and_associate_fields(params)
        content_type |> Repo.preload([:layout, :flow, {:fields, :field_type}])

      changeset = {:error, _} ->
        changeset
    end
  end

  @spec fetch_and_associate_fields(ContentType.t(), map) :: list
  # Iterate throught the list of field types and associate with the content type
  defp fetch_and_associate_fields(content_type, %{"fields" => fields}) do
    fields
    |> Stream.map(fn x -> associate_c_type_and_fields(content_type, x) end)
    |> Enum.to_list()
  end

  defp fetch_and_associate_fields(_content_type, _params), do: nil

  @spec associate_c_type_and_fields(ContentType.t(), map) ::
          {:ok, ContentTypeField.t()} | {:error, Ecto.Changeset.t()} | nil
  # Fetch and associate field types with the content type
  defp associate_c_type_and_fields(c_type, %{"key" => key, "field_type_id" => field_type_id}) do
    field_type_id
    |> get_field_type
    |> case do
      %FieldType{} = field_type ->
        field_type
        |> build_assoc(:fields, content_type: c_type)
        |> ContentTypeField.changeset(%{name: key})
        |> Repo.insert()

      nil ->
        nil
    end
  end

  defp associate_c_type_and_fields(_c_type, _field), do: nil

  @doc """
  List all engines.
  """
  @spec engines_list(map) :: map
  def engines_list(params) do
    Repo.paginate(Engine, params)
  end

  @doc """
  List all layouts.
  """
  @spec layout_index(User.t(), map) :: map
  def layout_index(%{organisation_id: org_id}, params) do
    from(l in Layout,
      where: l.organisation_id == ^org_id,
      order_by: [desc: l.id],
      preload: [:engine, :assets]
    )
    |> Repo.paginate(params)
  end

  @doc """
  Show a layout.
  """
  @spec show_layout(binary) :: %Layout{engine: Engine.t(), creator: User.t()}
  def show_layout(uuid) do
    get_layout(uuid)
    |> Repo.preload([:engine, :creator, :assets])
  end

  @doc """
  Get a layout from its UUID.
  """
  @spec get_layout(binary) :: Layout.t()
  def get_layout(uuid) do
    Repo.get_by(Layout, uuid: uuid)
  end

  @doc """
  Update a layout.
  """
  @spec update_layout(Layout.t(), User.t(), map) :: %Layout{engine: Engine.t(), creator: User.t()}
  def update_layout(layout, current_user, %{"engine_uuid" => engine_uuid} = params) do
    %Engine{id: id} = get_engine(engine_uuid)
    {_, params} = Map.pop(params, "engine_uuid")
    params = params |> Map.merge(%{"engine_id" => id})
    update_layout(layout, current_user, params)
  end

  def update_layout(layout, %{id: user_id} = current_user, params) do
    layout
    |> Layout.update_changeset(params)
    |> Spur.update(%{actor: "#{user_id}"})
    |> case do
      {:error, _} = changeset ->
        changeset

      {:ok, layout} ->
        layout |> fetch_and_associcate_assets(current_user, params)
        layout |> Repo.preload([:engine, :creator, :assets])
    end
  end

  @doc """
  Delete a layout.
  """
  @spec delete_layout(Layout.t(), User.t()) :: {:ok, Layout.t()} | {:error, Ecto.Changeset.t()}
  def delete_layout(layout, %User{id: id}) do
    layout
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.no_assoc_constraint(
      :content_types,
      message:
        "Cannot delete the layout. Some Content types depend on this layout. Update those content types and then try again.!"
    )
    |> Spur.delete(%{actor: "#{id}"})
  end

  @doc """
  List all content types.
  """
  @spec content_type_index(User.t(), map) :: map
  def content_type_index(%{organisation_id: org_id}, params) do
    from(ct in ContentType,
      where: ct.organisation_id == ^org_id,
      order_by: [desc: ct.id],
      preload: [:layout, :flow, {:fields, :field_type}]
    )
    |> Repo.paginate(params)
  end

  @doc """
  Show a content type.
  """
  @spec show_content_type(binary) :: %ContentType{layout: %Layout{}, creator: %User{}}
  def show_content_type(uuid) do
    get_content_type(uuid)
    |> Repo.preload([:layout, :creator, [{:flow, :states}, {:fields, :field_type}]])
  end

  @doc """
  Get a content type from its UUID.
  """
  @spec get_content_type(binary) :: ContentType.t()
  def get_content_type(uuid) do
    Repo.get_by(ContentType, uuid: uuid)
  end

  @doc """
  Update a content type.
  """
  @spec update_content_type(ContentType.t(), User.t(), map) ::
          %ContentType{
            layout: Layout.t(),
            creator: User.t()
          }
          | {:error, Ecto.Changeset.t()}
  def update_content_type(
        content_type,
        user,
        %{"layout_uuid" => layout_uuid, "flow_uuid" => f_uuid} = params
      ) do
    %Layout{id: id} = get_layout(layout_uuid)
    %Flow{id: f_id} = Enterprise.get_flow(f_uuid)
    {_, params} = Map.pop(params, "layout_uuid")
    {_, params} = Map.pop(params, "flow_uuid")
    params = params |> Map.merge(%{"layout_id" => id, "flow_id" => f_id})
    update_content_type(content_type, user, params)
  end

  def update_content_type(content_type, %User{id: id}, params) do
    content_type
    |> ContentType.update_changeset(params)
    |> Spur.update(%{actor: "#{id}"})
    |> case do
      {:error, _} = changeset ->
        changeset

      {:ok, content_type} ->
        content_type |> fetch_and_associate_fields(params)

        content_type
        |> Repo.preload([:layout, :creator, [{:flow, :states}, {:fields, :field_type}]])
    end
  end

  @doc """
  Delete a content type.
  """
  @spec delete_content_type(ContentType.t(), User.t()) ::
          {:ok, ContentType.t()} | {:error, Ecto.Changeset.t()}
  def delete_content_type(content_type, %User{id: id}) do
    content_type
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.no_assoc_constraint(
      :instances,
      message:
        "Cannot delete the content type. There are many contents under this content type. Delete those contents and try again.!"
    )
    |> Spur.delete(%{actor: "#{id}"})
  end

  @doc """
  Create a new instance.
  """
  @spec create_instance(User.t(), ContentType.t(), State.t(), map) ::
          %Instance{content_type: ContentType.t(), state: State.t()}
          | {:error, Ecto.Changeset.t()}
  def create_instance(current_user, %{id: c_id, prefix: prefix} = c_type, state, params) do
    instance_id = c_id |> create_instance_id(prefix)
    params = params |> Map.merge(%{"instance_id" => instance_id})

    c_type
    |> build_assoc(:instances, state: state, creator: current_user)
    |> Instance.changeset(params)
    |> Spur.insert()
    |> case do
      {:ok, content} ->
        Task.start(fn -> create_or_update_counter(c_type) end)
        content |> Repo.preload([:content_type, :state])

      changeset = {:error, _} ->
        changeset
    end
  end

  # Create Instance ID from the prefix of the content type
  @spec create_instance_id(integer, binary) :: binary
  defp create_instance_id(c_id, prefix) do
    instance_count =
      c_id
      |> get_counter_count_from_content_type_id
      |> add(1)
      |> to_string
      |> String.pad_leading(4, "0")

    concat_strings(prefix, instance_count)
  end

  # Create count of instances created for a content type from its ID
  @spec get_counter_count_from_content_type_id(integer) :: integer
  defp get_counter_count_from_content_type_id(c_type_id) do
    c_type_id
    |> get_counter_from_content_type_id
    |> case do
      nil ->
        0

      %Counter{count: count} ->
        count
    end
  end

  defp get_counter_from_content_type_id(c_type_id) do
    from(c in Counter, where: c.subject == ^"ContentType:#{c_type_id}")
    |> Repo.one()
  end

  # Create or update the counter of a content type.integer()
  @spec create_or_update_counter(ContentType.t()) :: {:ok, Counter} | {:error, Ecto.Changeset.t()}
  def create_or_update_counter(%ContentType{id: id}) do
    id
    |> get_counter_from_content_type_id
    |> case do
      nil ->
        Counter.changeset(%Counter{}, %{subject: "ContentType:#{id}", count: 1})

      %Counter{count: count} = counter ->
        count = count |> add(1)
        counter |> Counter.changeset(%{count: count})
    end
    |> Repo.insert_or_update()
  end

  # Add two integers
  @spec add(integer, integer) :: integer
  defp add(num1, num2) do
    num1 + num2
  end

  @doc """
  List all instances under an organisation.
  """
  @spec instance_index_of_an_organisation(User.t(), map) :: map
  def instance_index_of_an_organisation(%{organisation_id: org_id}, params) do
    from(i in Instance,
      join: u in User,
      where: u.organisation_id == ^org_id and i.creator_id == u.id,
      order_by: [desc: i.id],
      preload: [:content_type, :state]
    )
    |> Repo.paginate(params)
  end

  @doc """
  List all instances under a content types.
  """
  @spec instance_index(binary, map) :: map
  def instance_index(c_type_uuid, params) do
    from(i in Instance,
      join: ct in ContentType,
      where: ct.uuid == ^c_type_uuid and i.content_type_id == ct.id,
      order_by: [desc: i.id],
      preload: [:content_type, :state]
    )
    |> Repo.paginate(params)
  end

  @doc """
  Get an instance from its UUID.
  """
  @spec get_instance(binary) :: Instance.t()
  def get_instance(uuid) do
    Repo.get_by(Instance, uuid: uuid)
  end

  @doc """
  Show an instance.
  """
  @spec show_instance(binary) ::
          %Instance{creator: User.t(), content_type: ContentType.t(), state: State.t()} | nil
  def show_instance(instance_uuid) do
    instance_uuid
    |> get_instance()
    |> Repo.preload([:creator, [{:content_type, :layout}], :state])
    |> get_built_document()
  end

  # Get the build document of the given instance
  @spec get_built_document(Instance.t()) :: Instance.t() | nil
  defp get_built_document(%{id: id, instance_id: instance_id} = instance) do
    from(h in History,
      where: h.exit_code == 0,
      where: h.content_id == ^id,
      order_by: [desc: h.inserted_at],
      limit: 1
    )
    |> Repo.one()
    |> case do
      nil ->
        instance

      %History{} ->
        doc_url = "uploads/contents/#{instance_id}/final.pdf"
        instance |> Map.put(:build, doc_url)
    end
  end

  defp get_built_document(nil) do
    nil
  end

  @doc """
  Update an instance.
  """
  @spec update_instance(Instance.t(), User.t(), map) ::
          %Instance{content_type: ContentType.t(), state: State.t(), creator: Creator.t()}
          | {:error, Ecto.Changeset.t()}

  def update_instance(instance, user, %{"state_uuid" => state_uuid} = params) do
    %State{id: id} = Enterprise.get_state(state_uuid)
    {_, params} = Map.pop(params, "state_uuid")
    params = params |> Map.merge(%{"state_id" => id})
    update_instance(instance, user, params)
  end

  def update_instance(instance, %User{id: id}, params) do
    instance
    |> Instance.update_changeset(params)
    |> Spur.update(%{actor: "#{id}"})
    |> case do
      {:ok, instance} ->
        instance
        |> Repo.preload([:creator, [{:content_type, :layout}], :state])
        |> get_built_document()

      {:error, _} = changeset ->
        changeset
    end
  end

  @doc """
  Delete an instance.
  """
  @spec delete_instance(Instance.t(), User.t()) ::
          {:ok, Instance.t()} | {:error, Ecto.Changeset.t()}
  def delete_instance(instance, %User{id: id}) do
    instance
    |> Spur.delete(%{actor: "#{id}"})
  end

  @doc """
  Get an engine from its UUID.
  """
  @spec get_engine(binary) :: Engine.t() | nil
  def get_engine(engine_uuid) do
    Repo.get_by(Engine, uuid: engine_uuid)
  end

  @doc """
  Create a theme.
  """
  @spec create_theme(User.t(), map) :: {:ok, Theme.t()} | {:error, Ecto.Changeset.t()}
  def create_theme(%{organisation_id: org_id} = current_user, params) do
    params = params |> Map.merge(%{"organisation_id" => org_id})

    current_user
    |> build_assoc(:themes)
    |> Theme.changeset(params)
    |> Spur.insert()
    |> case do
      {:ok, theme} ->
        theme |> theme_file_upload(params)

      {:error, _} = changeset ->
        changeset
    end
  end

  @doc """
  Upload theme file.
  """
  @spec theme_file_upload(Theme.t(), map) :: {:ok, %Theme{}} | {:error, Ecto.Changeset.t()}
  def theme_file_upload(theme, %{"file" => _} = params) do
    theme |> Theme.file_changeset(params) |> Repo.update()
  end

  def theme_file_upload(theme, _params) do
    {:ok, theme}
  end

  @doc """
  Index of themes inside current user's organisation.
  """
  @spec theme_index(User.t(), map) :: map
  def theme_index(%User{organisation_id: org_id}, params) do
    from(t in Theme, where: t.organisation_id == ^org_id, order_by: [desc: t.id])
    |> Repo.paginate(params)
  end

  @doc """
  Get a theme from its UUID.
  """
  @spec get_theme(binary) :: Theme.t() | nil
  def get_theme(theme_uuid) do
    Repo.get_by(Theme, uuid: theme_uuid)
  end

  @doc """
  Show a theme.
  """
  @spec show_theme(binary) :: %Theme{creator: User.t()} | nil
  def show_theme(theme_uuid) do
    theme_uuid |> get_theme() |> Repo.preload([:creator])
  end

  @doc """
  Update a theme.
  """
  @spec update_theme(Theme.t(), User.t(), map) :: {:ok, Theme.t()} | {:error, Ecto.Changeset.t()}
  def update_theme(theme, %User{id: id}, params) do
    theme |> Theme.update_changeset(params) |> Spur.update(%{actor: "#{id}"})
  end

  @doc """
  Delete a theme.
  """
  @spec delete_theme(Theme.t(), User.t()) :: {:ok, Theme.t()}
  def delete_theme(theme, %User{id: id}) do
    theme
    |> Spur.delete(%{actor: "#{id}"})
  end

  @doc """
  Create a data template.
  """
  @spec create_data_template(User.t(), ContentType.t(), map) ::
          {:ok, DataTemplate.t()} | {:error, Ecto.Changeset.t()}
  def create_data_template(current_user, c_type, params) do
    current_user
    |> build_assoc(:data_templates, content_type: c_type)
    |> DataTemplate.changeset(params)
    |> Spur.insert()
  end

  @doc """
  List all data templates under a content types.
  """
  @spec data_template_index(binary, map) :: map
  def data_template_index(c_type_uuid, params) do
    from(dt in DataTemplate,
      join: ct in ContentType,
      where: ct.uuid == ^c_type_uuid and dt.content_type_id == ct.id,
      order_by: [desc: dt.id]
    )
    |> Repo.paginate(params)
  end

  @doc """
  List all data templates under current user's organisation.
  """
  @spec data_templates_index_of_an_organisation(User.t(), map) :: map
  def data_templates_index_of_an_organisation(%{organisation_id: org_id}, params) do
    from(dt in DataTemplate,
      join: u in User,
      where: u.organisation_id == ^org_id and dt.creator_id == u.id,
      order_by: [desc: dt.id]
    )
    |> Repo.paginate(params)
  end

  @doc """
  Get a data template from its uuid
  """
  @spec get_d_template(binary) :: DataTemplat.t() | nil
  def get_d_template(d_temp_uuid) do
    Repo.get_by(DataTemplate, uuid: d_temp_uuid)
  end

  @doc """
  Show a data template.
  """
  @spec show_d_template(binary) ::
          %DataTemplate{creator: User.t(), content_type: ContentType.t()} | nil
  def show_d_template(d_temp_uuid) do
    d_temp_uuid |> get_d_template() |> Repo.preload([:creator, :content_type])
  end

  @doc """
  Update a data template
  """
  @spec update_data_template(DataTemplate.t(), User.t(), map) ::
          %DataTemplate{creator: User.t(), content_type: ContentType.t()}
          | {:error, Ecto.Changeset.t()}
  def update_data_template(d_temp, %User{id: id}, params) do
    d_temp
    |> DataTemplate.changeset(params)
    |> Spur.update(%{actor: "#{id}"})
    |> case do
      {:ok, d_temp} ->
        d_temp |> Repo.preload([:creator, :content_type])

      {:error, _} = changeset ->
        changeset
    end
  end

  @doc """
  Delete a data template
  """
  @spec delete_data_template(DataTemplate.t(), User.t()) :: {:ok, DataTemplate.t()}
  def delete_data_template(d_temp, %User{id: id}) do
    d_temp |> Spur.delete(%{actor: "#{id}"})
  end

  @doc """
  Create an asset.
  """
  @spec create_asset(User.t(), map) :: {:ok, Asset.t()}
  def create_asset(%{organisation_id: org_id} = current_user, params) do
    params = params |> Map.merge(%{"organisation_id" => org_id})

    current_user
    |> build_assoc(:assets)
    |> Asset.changeset(params)
    |> Spur.insert()
    |> case do
      {:ok, asset} ->
        asset |> asset_file_upload(params)

      {:error, _} = changeset ->
        changeset
    end
  end

  @doc """
  Upload asset file.
  """
  @spec asset_file_upload(Asset.t(), map) :: {:ok, %Asset{}} | {:error, Ecto.Changeset.t()}
  def asset_file_upload(asset, %{"file" => _} = params) do
    asset |> Asset.file_changeset(params) |> Repo.update()
  end

  def asset_file_upload(asset, _params) do
    {:ok, asset}
  end

  @doc """
  Index of all assets in an organisation.
  """
  @spec asset_index(integer, map) :: map
  def asset_index(organisation_id, params) do
    from(a in Asset, where: a.organisation_id == ^organisation_id, order_by: [desc: a.id])
    |> Repo.paginate(params)
  end

  @doc """
  Show an asset.
  """
  @spec show_asset(binary) :: %Asset{creator: User.t()}
  def show_asset(asset_uuid) do
    asset_uuid
    |> get_asset()
    |> Repo.preload([:creator])
  end

  @doc """
  Get an asset from its UUID.
  """
  @spec get_asset(binary) :: Asset.t()
  def get_asset(uuid) do
    Repo.get_by(Asset, uuid: uuid)
  end

  @doc """
  Update an asset.
  """
  @spec update_asset(Asset.t(), User.t(), map) :: {:ok, Asset.t()}
  def update_asset(asset, %User{id: id}, params) do
    asset |> Asset.update_changeset(params) |> Spur.update(%{actor: "#{id}"})
  end

  @doc """
  Delete an asset.
  """
  @spec delete_asset(Asset.t(), User.t()) :: {:ok, Asset.t()}
  def delete_asset(asset, %User{id: id}) do
    asset |> Spur.delete(%{actor: "#{id}"})
  end

  @doc """
  Preload assets of a layout.
  """
  @spec preload_asset(Layout.t()) :: Layout.t()
  def preload_asset(layout) do
    layout |> Repo.preload([:assets])
  end

  @doc """
  Build a PDF document.
  """

  @spec build_doc(Instance.t(), Layout.t()) :: {any, integer}
  def build_doc(%Instance{instance_id: u_id, content_type: c_type} = instance, %Layout{
        slug: slug,
        assets: assets
      }) do
    File.mkdir_p("uploads/contents/#{u_id}")
    System.cmd("cp", ["-a", "lib/slugs/#{slug}/", "uploads/contents/#{u_id}"])
    task = Task.async(fn -> generate_qr(instance) end)
    Task.start(fn -> move_old_builds(u_id) end)
    c_type = c_type |> Repo.preload([:fields])

    header =
      c_type.fields
      |> Enum.reduce("--- \n", fn x, acc ->
        find_header_values(x, instance.serialized, acc)
      end)

    header = assets |> Enum.reduce(header, fn x, acc -> find_header_values(x, acc) end)
    qr_code = Task.await(task)

    header =
      header
      |> concat_strings("qrcode: #{qr_code} \n")
      |> concat_strings("path: uploads/contents/#{u_id}\n")
      |> concat_strings("--- \n")

    content = """
    #{header}
    #{instance.raw}
    """

    File.write("uploads/contents/#{u_id}/content.md", content)

    pandoc_commands = [
      "uploads/contents/#{u_id}/content.md",
      "--template=uploads/contents/#{u_id}/template.tex",
      "--pdf-engine=xelatex",
      "-o",
      "uploads/contents/#{u_id}/final.pdf"
    ]

    System.cmd("pandoc", pandoc_commands)
  end

  # Find the header values for the content.md file from the serialized data of an instance.
  @spec find_header_values(ContentTypeField.t(), map, String.t()) :: String.t()
  defp find_header_values(%ContentTypeField{name: key}, serialized, acc) do
    serialized
    |> Enum.find(fn {k, _} -> k == key end)
    |> case do
      nil ->
        acc

      {_, value} ->
        concat_strings(acc, "#{key}: #{value} \n")
    end
  end

  # Find the header values for the content.md file from the assets of the layout used.
  @spec find_header_values(Asset.t(), String.t()) :: String.t()
  defp find_header_values(%Asset{name: name, file: file} = asset, acc) do
    <<_first::utf8, rest::binary>> = AssetUploader |> generate_url(file, asset)
    concat_strings(acc, "#{name}: #{rest} \n")
  end

  # Generate url.
  @spec generate_url(any, String.t(), map) :: String.t()
  defp generate_url(uploader, file, scope) do
    uploader.url({file, scope}, signed: true)
  end

  # Generate QR code with the UUID of the given Instance.
  @spec generate_qr(Instance.t()) :: String.t()
  defp generate_qr(%Instance{uuid: uuid, instance_id: i_id}) do
    qr_code_png =
      uuid
      |> EQRCode.encode()
      |> EQRCode.png()

    destination = "uploads/contents/#{i_id}/qr.png"
    File.write(destination, qr_code_png, [:binary])
    destination
  end

  @doc """
  Concat two strings.
  """
  @spec concat_strings(String.t(), String.t()) :: String.t()
  def concat_strings(string1, string2) do
    string1 <> string2
  end

  # Move old builds to the history folder
  @spec move_old_builds(String.t()) :: {:ok, non_neg_integer()}
  defp move_old_builds(u_id) do
    path = "uploads/contents/#{u_id}/"
    history_path = concat_strings(path, "history/")
    old_file = concat_strings(path, "final.pdf")
    File.mkdir_p(history_path)

    history_file =
      history_path
      |> File.ls!()
      |> Enum.sort(:desc)
      |> case do
        ["final-" <> version | _] ->
          ["v" <> version | _] = version |> String.split(".pdf")
          version = version |> String.to_integer() |> add(1)
          concat_strings(history_path, "final-v#{version}.pdf")

        [] ->
          concat_strings(history_path, "final-v1.pdf")
      end

    File.copy(old_file, history_file)
  end

  @doc """
  Insert the build history of the given instance.
  """
  @spec add_build_history(User.t(), Instance.t(), map) :: History.t()
  def add_build_history(current_user, instance, params) do
    params = create_build_history_params(params)

    current_user
    |> build_assoc(:build_histories, content: instance)
    |> History.changeset(params)
    |> Repo.insert!()
  end

  # Create params to insert build history
  # Build history Status will be "success" when exit code is 0
  @spec create_build_history_params(map) :: map
  defp create_build_history_params(%{exit_code: exit_code} = params) when exit_code == 0 do
    %{status: "success"} |> Map.merge(params) |> calculate_build_delay
  end

  # Build history Status will be "failed" when exit code is not 0
  defp create_build_history_params(params) do
    %{status: "failed"} |> Map.merge(params) |> calculate_build_delay
  end

  # Calculate the delay in the build process from the start and end time in the params.
  @spec calculate_build_delay(map) :: map
  defp calculate_build_delay(%{start_time: start_time, end_time: end_time} = params) do
    delay = Timex.diff(end_time, start_time, :millisecond)
    params |> Map.merge(%{delay: delay})
  end

  @doc """

  Create a Block
  """
  @spec create_block(User.t(), map) :: Block.t()

  def create_block(%{organisation_id: org_id} = current_user, params) do
    params = params |> Map.merge(%{"organisation_id" => org_id})

    current_user
    |> build_assoc(:blocks)
    |> Block.changeset(params)
    |> Repo.insert()
    |> case do
      {:ok, block} ->
        block

      {:error, _} = changeset ->
        changeset
    end
  end

  def create_chart(url, id) do
    {:ok, response} = HTTPoison.get(url)
    File.write!("#{File.cwd!()}/uploads/assets/chart/chart#{id}.pdf", response.body)
  end

  def create_go_chart(body, id) do
    File.write!("#{File.cwd!()}/uploads/assets/chart/chart#{id}.svg", body)
  end

  require IEx

  def generate_chart(body) do
    IEx.pry()

    %HTTPotion.Response{body: response_body} =
      HTTPotion.post!("https://quickchart.io/chart/create",
        body: Poison.encode!(body),
        headers: [{"Accept", "application/json"}, {"Content-Type", "application/json"}]
      )

    Poison.decode!(response_body)
  end

  def generate_go_chart(body) do
    %HTTPotion.Response{body: response_body} =
      HTTPotion.post!("http://localhost:8080/chart",
        body: Poison.encode!(body),
        headers: [{"Accept", "application./json"}, {"Content-Type", "application/json"}]
      )

    response_body
  end

  def generate_quick_chart_data(%{"label" => label, "value" => value}) do

  Create a field type
  """
  @spec create_field_type(User.t(), map) :: {:ok, FieldType.t()}
  def create_field_type(current_user, params) do
    current_user
    |> build_assoc(:field_types)
    |> FieldType.changeset(params)
    |> Repo.insert()
  end

  @doc """
  Index of all field types.
  """
  @spec field_type_index(map) :: map
  def field_type_index(params) do
    from(ft in FieldType, order_by: [desc: ft.id])
    |> Repo.paginate(params)
  end

  @doc """
  Get a field type from its UUID.
  """
  @spec get_field_type(binary) :: FieldType.t()
  def get_field_type(field_type_uuid) do
    Repo.get_by(FieldType, uuid: field_type_uuid)
  end

  @doc """
  Update a field type
  """
  @spec update_field_type(FieldType.t(), map) :: FieldType.t() | {:error, Ecto.Changeset.t()}
  def update_field_type(field_type, params) do
    field_type
    |> FieldType.changeset(params)
    |> Repo.update()
  end

  def delete_field_type(field_type) do
    field_type
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.no_assoc_constraint(
      :fields,
      message:
        "Cannot delete the field type. Some Content types depend on this field type. Update those content types and then try again.!"
    )
    |> Repo.delete()

  end
end

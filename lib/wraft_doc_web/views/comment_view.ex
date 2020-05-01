defmodule WraftDocWeb.Api.V1.CommentView do
  use WraftDocWeb, :view
  alias __MODULE__
  alias WraftDocWeb.Api.V1.ProfileView

  def render("comment.json", %{comment: comment}) do
    profile_pic = ProfileView.generate_url(comment.user.profile)

    %{
      id: comment.uuid,
      comment: comment.comment,
      is_parent: comment.is_parent,
      parent_id: comment.parent_id,
      master: comment.master,
      master_id: comment.master_id,
      user_name: comment.user.name,
      profile_pic: profile_pic,
      inserted_at: comment.inserted_at,
      updated_at: comment.updated_at
    }
  end

  def render("reply_count.json", %{reply_count: reply_count}) do
    %{reply_count: reply_count}
  end

  def render("index.json", %{
        comments: comments,
        page_number: page_number,
        total_pages: total_pages,
        total_entries: total_entries
      }) do
    %{
      comments: render_many(comments, CommentView, "comment.json", as: :comment),
      page_number: page_number,
      total_pages: total_pages,
      total_entries: total_entries
    }
  end

  def render("delete.json", %{comment: comment}) do
    %{
      id: comment.uuid,
      comment: comment.comment,
      is_parent: comment.is_parent,
      parent_id: comment.parent_id,
      master: comment.master,
      master_id: comment.master_id,
      inserted_at: comment.inserted_at,
      updated_at: comment.updated_at
    }
  end
end

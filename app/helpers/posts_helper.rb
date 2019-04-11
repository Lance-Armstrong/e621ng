module PostsHelper
  def post_search_counts_enabled?
    Danbooru.config.enable_post_search_counts && Danbooru.config.reportbooru_server.present? && Danbooru.config.reportbooru_key.present?
  end

  def discover_mode?
    params[:tags] =~ /order:rank/ || params[:action] =~ /searches|viewed/
  end

  def next_page_url
    current_page = (params[:page] || 1).to_i
    url_for(nav_params_for(current_page + 1)).html_safe
  end

  def prev_page_url
    current_page = (params[:page] || 1).to_i
    if current_page >= 2
      url_for(nav_params_for(current_page - 1)).html_safe
    else
      nil
    end
  end

  def missed_post_search_count_js
    return nil unless post_search_counts_enabled?

    if params[:ms] == "1" && @post_set.post_count == 0 && @post_set.is_single_tag?
      session_id = session.id
      verifier = ActiveSupport::MessageVerifier.new(Danbooru.config.reportbooru_key, serializer: JSON, digest: "SHA256")
      sig = verifier.generate("#{params[:tags]},#{session_id}")
      return render("posts/partials/index/missed_search_count", sig: sig)
    end
  end

  def post_search_count_js
    return nil unless post_search_counts_enabled?

    if action_name == "index" && params[:page].nil?
      tags = Tag.scan_query(params[:tags]).sort.join(" ")

      if tags.present?
        key = "ps-#{tags}"
        value = session.id
        verifier = ActiveSupport::MessageVerifier.new(Danbooru.config.reportbooru_key, serializer: JSON, digest: "SHA256")
        sig = verifier.generate("#{key},#{value}")
        return render("posts/partials/index/search_count", sig: sig)
      end
    end

    return nil
  end

  def post_view_count_js
    return nil unless post_search_counts_enabled?

    msg = "#{params[:id]},#{session.id}"
    msg = ActiveSupport::MessageVerifier.new(Danbooru.config.reportbooru_key, serializer: JSON, digest: "SHA256").generate(msg)
    return render("posts/partials/show/view_count", msg: msg)
  end

  def common_searches_html(user)
    return nil unless post_search_counts_enabled?
    return nil unless user.is_platinum?
    return nil unless user.enable_recent_searches?

    key = "uid"
    value = user.id
    verifier = ActiveSupport::MessageVerifier.new(Danbooru.config.reportbooru_key, serializer: JSON, digest: "SHA256")
    sig = verifier.generate("#{key},#{value}")
    render("users/common_searches", user: user, sig: sig)
  end

  def post_source_tag(post)
    if post.source =~ %r!\Ahttp://img\d+\.pixiv\.net/img/([^\/]+)/!i
      text = "pixiv/<wbr>#{wordbreakify($1)}".html_safe
      source_search = "source:pixiv/#{$1}/"
    elsif post.source =~ %r!\Ahttp://i\d\.pixiv\.net/img\d+/img/([^\/]+)/!i
      text = "pixiv/<wbr>#{wordbreakify($1)}".html_safe
      source_search = "source:pixiv/#{$1}/"
    elsif post.source =~ %r{\Ahttps?://}i
      text = post.normalized_source.sub(/\Ahttps?:\/\/(?:www\.)?/i, "")
      text = truncate(text, length: 20)
      source_search = "source:#{post.source.sub(/[^\/]*$/, "")}"
    end

    # Only allow http:// and https:// links. Disallow javascript: links.
    if post.normalized_source =~ %r!\Ahttps?://!i
      source_link = link_to(text, post.normalized_source)
    else
      source_link = truncate(post.source, :length => 100)
    end

    if CurrentUser.is_builder? && !source_search.blank?
      source_link + "&nbsp;".html_safe + link_to("&raquo;".html_safe, posts_path(:tags => source_search), :rel => "nofollow")
    else
      source_link
    end
  end

  def post_favlist(post)
    post.favorited_users.reverse_each.map {|user| link_to_user(user)}.join(", ").html_safe
  end

  def has_parent_message(post, parent_post_set)
    html = ""

    html << "This post belongs to a "
    html << link_to("parent", posts_path(:tags => "parent:#{post.parent_id}"))
    html << " (deleted)" if parent_post_set.parent.first.is_deleted?

    sibling_count = parent_post_set.children.count - 1
    if sibling_count > 0
      html << " and has "
      text = sibling_count == 1 ? "a sibling" : "#{sibling_count} siblings"
      html << link_to(text, posts_path(:tags => "parent:#{post.parent_id}"))
    end

    html << " (#{link_to("learn more", wiki_pages_path(:title => "help:post_relationships"))}) "

    html << link_to("&laquo; hide".html_safe, "#", :id => "has-parent-relationship-preview-link")

    html.html_safe
  end

  def has_children_message(post, children_post_set)
    html = ""

    html << "This post has "
    text = children_post_set.children.count == 1 ? "a child" : "#{children_post_set.children.count} children"
    html << link_to(text, posts_path(:tags => "parent:#{post.id}"))

    html << " (#{link_to("learn more", wiki_pages_path(:title => "help:post_relationships"))}) "

    html << link_to("&laquo; hide".html_safe, "#", :id => "has-children-relationship-preview-link")

    html.html_safe
  end

  def pool_link(pool)
    render("posts/partials/show/pool_link", post: @post, pool: pool)
  end

  def is_pool_selected?(pool)
    return false if params.has_key?(:q)
    return false if params.has_key?(:post_set_id)
    return false unless params.has_key?(:pool_id)
    return params[:pool_id].to_i == pool.id
  end

  def is_post_set_selected?(post_set)
    return false if params.has_key?(:q)
    return false if params.has_key?(:pool_id)
    return false unless params.has_key?(:post_set_id)
    return params[:post_set_id].to_i == post_set.id
  end

  def show_tag_change_notice?
    Tag.scan_query(params[:tags]).size == 1 && TagChangeNoticeService.get_forum_topic_id(params[:tags])
  end

  private

  def nav_params_for(page)
    query_params = params.except(:controller, :action, :id).merge(page: page).permit!
    {params: query_params}
  end

  def post_vote_block(post, vote)
    voted = !vote.nil?
    vote_score = voted ? vote.score : 0
    post_score = post.score

    def score_class(score)
      return 'score-neutral' if score == 0
      score > 0 ? 'score-positive' : 'score-negative'
    end

    def confirm_score_class(score, want)
      return 'score-neutral' if score != want || score == 0
      score_class(score)
    end

    up_tag = tag.span(tag.a('&#x25B2;'.html_safe, class: 'post-vote-up-link', 'data-id': post.id),
                    class: confirm_score_class(vote_score, 1),
                    id: "post-vote-up-#{post.id}")
    down_tag = tag.span(tag.a('&#x25BC;'.html_safe, class: 'post-vote-down-link', 'data-id': post.id),
                      class: confirm_score_class(vote_score, -1),
                      id: "post-vote-down-#{post.id}")
    vote_block = tag.span(" (vote ".html_safe + up_tag +  "/" + down_tag + ")")
    score_tag = tag.span(post.score, class: "post-score #{score_class(post_score)}", id: "post-score-#{post.id}", title: "#{post.up_score} up/#{post.down_score} down")
    score_tag + (CurrentUser.is_voter? ? vote_block : '')
  end
end

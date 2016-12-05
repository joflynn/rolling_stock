require './views/page'

module Views
  class Game < Page
    needs :game

    def render_main
      render_new if game.new_game?
      render_game
      widget Deck, {
        available_companies: game.companies,
        pending_companies: game.pending_companies,
        all_companies: game.all_companies,
        company_deck: game.company_deck,
        cost_of_ownership: {},
      }
    end

    def render_new
      div do
        game.players.values.map do |player|
          div player.name
        end

        render_join_button if !game.players[app.current_user.id] && game.new_game?
        render_start_button if game.user == app.current_user
      end
    end

    def render_game
      game.players.values.map do |player|
        widget PlayerHoldings, player: player
      end
    end

    def render_join_button
      form action: app.path(game, 'join'), method: 'post' do
        rawtext app.csrf_tag
        input type: 'submit', value: 'Join As Player'
      end
    end

    def render_start_button
      form action: app.path(game, 'start'), method: 'post' do
        rawtext app.csrf_tag
        input type: 'submit', value: 'Start Game'
      end
    end
  end
end

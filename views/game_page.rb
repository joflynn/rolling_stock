require './views/page'

module Views
  class GamePage < Page
    needs :game

    def page_title
      "Game #{game.id}"
    end

    def render_main
      render_js

      update_style = inline(
        background_color: 'lightgreen',
        text_align: 'center',
        font_weight: 'bold',
        font_size: '18px',
        padding: '5px',
        cursor: 'pointer',
        display: 'none',
      )

      div id: 'update', style: update_style, onclick: 'GamePage.update()' do
        text 'Game Updated (click to refresh)'
      end

      div id: 'game_container' do
        widget Game, game: game, current_user: app.current_user
      end
    end

    def render_js
      script <<~JS
        var init = function() {
          GamePage.watch();

          $('#log_chat_input').focus();

          // prevents double taps and also submits the value
          $('form :submit').click(function() {
            $(this).prop("disabled", true).closest('form').append($('<input/>', {
              type: 'hidden',
              name: this.name,
              value: this.value,
            })).submit();
          });
        }

        $(document).ready(init);

        var GamePage = {
          html: "",
          changed: false,
          scrolled: false,

          update: function() {
            $('#game_container').html(this.html);
            $("[name='_csrf']").attr('value', '#{app.csrf_token}');
            $('#update').hide();
            this.changed = false;
            this.scrolled = false;
            this.html = "";
            this.watch();
          },

          watch: function() {
            $('form').on('input change', function() {
              GamePage.changed = true;
            });
          },
        }
      JS

      return if game.check_point

      script <<~JS
        var connection = new Connection(BaseSocketURL + '/game/#{game.id}/ws');

        connection.handler = function(msg) {
          GamePage.html = msg;
          GamePage.changed || GamePage.scrolled ? $('#update').show() : GamePage.update();
        };
      JS
    end
  end
end

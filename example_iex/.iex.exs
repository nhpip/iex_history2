

########################################################################
## If `runtime.exs` is not been used
##
Code.append_path("~/iex_history2/_build/dev/lib/iex_history2/ebin")
##
## Will override the default setting for opening a text editor from ctrl^l to ctrl^e
IExHistory2.initialize(scope: :local, navigation_keys: [editor: 05],
                       show_date: true, colors: [index: :red])
                       
########################################################################
## If the configuration is set in `runtime.exs` then just include this
## line in your `.iex.exs`
IExHistory2.initialize()


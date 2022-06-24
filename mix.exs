defmodule History.MixProject do
  use Mix.Project

  def project do
    [
      app: :history,
      version: "0.1.0",
      elixir: "~> 1.10",
      description: description(),
      package: package(),
      name: "History",	
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:iex]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
     {:ex_doc, "~> 0.28.4", only: :dev, runtime: false}
    ]
  end

  defp description() do
    "A few sentences (a paragraph) describing the project."
  end

  defp package() do
    [
      files: ~w(lib priv .formatter.exs mix.exs README* LICENSE*),
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/nhpip/history"}
    ]
  end
end

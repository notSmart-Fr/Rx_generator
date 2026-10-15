defmodule RxGenerator.Prescriptions.QRCode do
  @moduledoc """
  Generates clean, low-density 2D QR code vector SVG markup from prescription payloads.
  Wraps `eqrcode` with error correction level `:m`.
  """

  @doc """
  Generates an SVG string representation of the given QR payload string.

  Options:
  - `:viewbox` - boolean (default: true) to allow responsive CSS scaling
  - `:width` - width in pixels (optional)
  """
  @spec generate_svg(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def generate_svg(payload, opts \\ []) when is_binary(payload) do
    viewbox = Keyword.get(opts, :viewbox, true)

    try do
      svg =
        payload
        |> EQRCode.encode(:m)
        |> EQRCode.svg([viewbox: viewbox] ++ opts)

      {:ok, svg}
    rescue
      e -> {:error, e}
    end
  end
end

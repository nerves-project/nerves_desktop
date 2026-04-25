defmodule NervesDesktop.NervesKey do
  @moduledoc """
  Helper for generating NervesKey compatible certificates.
  """

  # 100 years in days
  @ca_validity_days 36500
  # 30 years in days
  @device_validity_days 10950

  @doc """
  Generates a new ECC CA (Signer) key and certificate valid for 100 years.
  Returns {:ok, {ca_cert_pem, ca_key_pem}}
  """
  def generate_ca(common_name \\ "NervesKey Signer") do
    key = X509.PrivateKey.new_ec(:secp256r1)
    
    cert = 
      X509.Certificate.self_signed(
        key, 
        "/CN=#{common_name}", 
        template: :root_ca, 
        validity: @ca_validity_days
      )
    
    {:ok, {X509.Certificate.to_pem(cert), X509.PrivateKey.to_pem(key)}}
  end

  @doc """
  Generates a device certificate signed by the provided CA valid for 30 years.
  """
  def generate_device_cert(serial, ca_cert_pem, ca_key_pem) do
    with {:ok, ca_cert} <- X509.Certificate.from_pem(ca_cert_pem),
         {:ok, ca_key} <- X509.PrivateKey.from_pem(ca_key_pem) do
      
      device_key = X509.PrivateKey.new_ec(:secp256r1)
      
      # NervesKey devices expect a certificate signed by the signer
      device_cert = 
        X509.Certificate.new(
          device_key, 
          "/CN=#{serial}", 
          ca_cert, 
          ca_key, 
          template: :server,
          validity: @device_validity_days
        )

      {:ok, X509.Certificate.to_pem(device_cert)}
    end
  end
end

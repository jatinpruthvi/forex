void OnStart()
{
   PrintFormat("ACCOUNT DETAILS: Login=%d, Balance=%.2f, Equity=%.2f, Currency=%s, Server=%s",
      AccountInfoInteger(ACCOUNT_LOGIN),
      AccountInfoDouble(ACCOUNT_BALANCE),
      AccountInfoDouble(ACCOUNT_EQUITY),
      AccountInfoString(ACCOUNT_CURRENCY),
      AccountInfoString(ACCOUNT_SERVER));
}

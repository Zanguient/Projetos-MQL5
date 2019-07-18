//+------------------------------------------------------------------+
//|                                                  DOL-Pearson.mq5 |
//|                                               Joscelino Oliveira |
//|                                   https://www.mathematice.mat.br |
//+------------------------------------------------------------------+
#property copyright "Joscelino Oliveira"
#property link      "https://www.mathematice.mat.br"
#property version   "1.00"
//+------------------------------------------------------------------+
//| Bibliotecas Padronizadas do MQL5                                 |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>          //-- classe para negociação
#include <Trade\TerminalInfo.mqh>   //-- Informacoes do Terminal
#include <Trade\AccountInfo.mqh>    //-- Informacoes da conta
#include <Trade\SymbolInfo.mqh>     //-- Informacoes do ativo

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Numerando o Expert                                               |
//+------------------------------------------------------------------+
#define EXPERT_MAGIC 9531597

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Classes a serem utilizadas                                       |
//+------------------------------------------------------------------+
CTerminalInfo terminal;
CTrade trade;
CAccountInfo myaccount;
CSymbolInfo mysymbol;

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//|  Input de dados pelo Usuario                                     |
//+------------------------------------------------------------------+
input double lote=5.00;       //Numero de contratos
input double stopLoss=5;   //Pontos para Stop Loss (Stop Fixo)
input double TakeProfit=5; //Pontos para Lucro (Stop Fixo)
input string inicio="09:00"; //Horario de inicio(entradas)
input string termino="16:00"; //Horario de termino(entradas)
input string fechamento="17:55"; //Horario de fechamento(entradas)
input bool usarTrailing=true;//Usar Trailing Stop?
input double TrailingStop=5; //Pontos para Stop Loss (Stop Movel)
input double tp_trailing=20.5;//Lucro alvo-fixo (Stop movel)
input double lucroMinimo=4;//Lucro minimo para mover Stop Movel
input double passo=4;//Passo do Stop Movel em pontos
input ulong desvio=2; //Slippage maximo em pontos
input int shift=0;

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//|   Variaveis globais                                              |
//+------------------------------------------------------------------+
MqlDateTime Time;
MqlDateTime horario_inicio,horario_termino,horario_fechamento,horario_atual;
double  Point();
datetime TimeLastBar;
long sumVolBuy=0;
long sumVolSell=0;
int maxTradesUm=0;
int maxTradesDois=0;
//--- sinalizador da presença de assinatura de recepção de eventos BookEvent 
bool book_subscribed=false; 
//--- matriz para receber solicitações a partir do livro de ofertas 
MqlBookInfo  book[]; 
int STDEV_Handle;
double STDEV_Buffer1[];
double STDEV_Buffer2[];
int ENTROPIA_Handle;
double ENTROPIA_Buffer[];
int HURST_Handle;
double HURST_Buffer1[];
double HURST_Buffer2[];
int RL_Handle;
double RL_Buffer1[];
double RL_Buffer2[];
double RL_Buffer3[];
double RL_Buffer4[];
double RL_Buffer5[];
MqlRates candle[];
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   
   RL_Handle=iCustom(_Symbol,_Period,"linear_regression.ex5",1,20,false);
   ArraySetAsSeries(RL_Buffer1,true);
   ArraySetAsSeries(RL_Buffer2,true);
   ArraySetAsSeries(RL_Buffer3,true);
   ArraySetAsSeries(RL_Buffer4,true);
   ArraySetAsSeries(RL_Buffer5,true);
   
   ENTROPIA_Handle=iCustom(_Symbol,_Period,"Entropy.ex5",15,0);
   ArraySetAsSeries(ENTROPIA_Buffer,true);
   
   HURST_Handle=iCustom(_Symbol,_Period,"Hurst exponent.ex5",30,PRICE_CLOSE);
   ArraySetAsSeries(HURST_Buffer1,true);
   ArraySetAsSeries(HURST_Buffer2,true);
   
   STDEV_Handle=iStdDev(_Symbol,_Period,20,0,MODE_SMA,PRICE_CLOSE);
   ArraySetAsSeries(STDEV_Buffer1,true);
   ArraySetAsSeries(STDEV_Buffer2,true);

   ArraySetAsSeries(candle, true); // Invertendo a indexacao dos candles
   
//-- Verificar preenchimento de lotes

    if (lote<5)
      {
         Alert("Volume (volume <5) invalido!!");  
         ExpertRemove();         
      } 
      
//---
   TimeToStruct(StringToTime(inicio),horario_inicio);         //+-------------------------------------+
   TimeToStruct(StringToTime(termino),horario_termino);       //| Conversão das variaveis para mql    |
   TimeToStruct(StringToTime(fechamento),horario_fechamento); //+-------------------------------------+

//verificação de erros nas entradas de horario

   if(horario_inicio.hour>horario_termino.hour || (horario_inicio.hour==horario_termino.hour && horario_inicio.min>horario_termino.min))
     {
      printf ( "Parametos de horarios invalidos!" );
      return INIT_FAILED;
     }
     
    if(horario_termino.hour>horario_fechamento.hour || (horario_termino.hour==horario_fechamento.hour && horario_termino.min>horario_fechamento.min))
     {
      printf("Parametos de horarios invalidos!");
      return INIT_FAILED;
      }
//--     
   RefreshRates();
   
//--- create timer

   EventSetMillisecondTimer(20);               //-- Eventos de timer recebidos uma vez por milisegundo
    
//--- ativamos a transmissão do livro de ofertas 
   if(MarketBookAdd(_Symbol)) 
     { 
      book_subscribed=true; 
      PrintFormat("%s: Função MarketBookAdd(%s) retornou true",__FUNCTION__,_Symbol); 
     } 
   else 
      PrintFormat("%s: Função MarketBookAdd(%s) retornou false! GetLastError()=%d",__FUNCTION__,_Symbol,GetLastError());   
  
//-- PARAMETROS DE PREENCHIMENTO DE ORDENS

   bool preenchimento=IsFillingTypeAllowed(_Symbol,ORDER_FILLING_RETURN);
   //---
   if(preenchimento=SYMBOL_FILLING_FOK)
      trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if(preenchimento=SYMBOL_FILLING_IOC)
      trade.SetTypeFilling(ORDER_FILLING_IOC);
   else
      trade.SetTypeFilling(ORDER_FILLING_RETURN);
      
//-- SLIPPAGE MAXIMO EM PONTOS
      
   trade.SetDeviationInPoints(desvio);                

//-- IMPRIME O TAMANHO DO PONTO DO ATIVO CORRENTE
    
   Print("O tamanho do ponto do ativo eh: ",_Point);   
     
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {

//--- destroy timer
   EventKillTimer();
//--- cancelamos nossa assinatura de recepção de eventos a partir do livro de ofertas 
   if(book_subscribed) 
     { 
      if(!MarketBookRelease(_Symbol)) 
         PrintFormat("%s: MarketBookRelease(%s) retornou false! GetLastError()=%d",_Symbol,GetLastError()); 
      else 
         book_subscribed=false; 
     } 
//--- A primeira maneira de obter o código de razão de desinicialização 
   Print(__FUNCTION__,"_Código do motivo de não inicialização = ",reason);
//--- A segunda maneira de obter o código de razão de desinicialização 
   Print(__FUNCTION__,"_UninitReason = ",getUninitReasonText(_UninitReason));

  }
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {

//-- ENVIO DE ORDENS

   Trades();
   
//-- TESTE NOVAS BARRAS

   NewBarDetect(); 
   if(NewBarDetect()==true)
     {
      Print("Nova barra!!");
     }
   
   if(!RefreshRates()){return;}
   
   datetime time  = iTime(Symbol(),Period(),shift); 
   double   open  = iOpen(Symbol(),Period(),shift); 
   double   high  = iHigh(Symbol(),Period(),shift); 
   double   low   = iLow(Symbol(),Period(),shift); 
   double   close = iClose(NULL,PERIOD_CURRENT,shift); 
   long     volume= iVolume(Symbol(),0,shift); 
   int      bars  = iBars(NULL,0); 
  
   Comment(Symbol(),",",EnumToString(Period()),"\n", 
           "Time: "  ,TimeToString(time,TIME_DATE|TIME_SECONDS),"\n", 
           "Open: "  ,DoubleToString(open,Digits()),"\n", 
           "High: "  ,DoubleToString(high,Digits()),"\n", 
           "Low: "   ,DoubleToString(low,Digits()),"\n", 
           "Close: " ,DoubleToString(close,Digits()),"\n", 
           "Volume: ",IntegerToString(volume),"\n", 
           "Bars: "  ,IntegerToString(bars),"\n",
           "Entropia anterior: ",NormalizeDouble(ENTROPIA_Buffer[1],6),"\n",
           "Entropia ATUAL: ",NormalizeDouble(ENTROPIA_Buffer[0],6),"\n",
           "Regressao Linear anterior: ",NormalizeDouble(RL_Buffer1[1],4),"\n",
           "Regressao Linear ATUAL: ",NormalizeDouble(RL_Buffer1[0],4),"\n",
           "Hurst: " ,NormalizeDouble(HURST_Buffer1[0],4),"\n",
           "Desvio Padrao: ",NormalizeDouble(STDEV_Buffer1[0],4),"\n"
           ); 
   

//-- PRE-CALCULO VOLUMES DE TICKS NAS PONTAS COMPRADORA E VENDEDORA

   MqlTick tick_array[]; 
   CopyTicks(_Symbol,tick_array,COPY_TICKS_TRADE,0,500);
   ArraySetAsSeries(tick_array,true);  
   MqlTick tick = tick_array[0];
   
   if(( tick.flags&TICK_FLAG_BUY)==TICK_FLAG_BUY)          //-- Se for um tick de compra
        {
         sumVolBuy+=(long)tick.volume;
         //--Print("Volume compra = ",sumVolBuy);
        }
     else if(( tick.flags&TICK_FLAG_SELL)==TICK_FLAG_SELL)   //-- Se for um tick de venda
         {
          sumVolSell+=(long)tick.volume;
          //--Print("Volume venda = ",sumVolSell);
         }
       
   ZeroMemory(tick_array);  
  }
  
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
  {
//-- BUFFERS DOS INDICADORES

   CopyBuffer(STDEV_Handle,0,0,5,STDEV_Buffer1);
   CopyBuffer(STDEV_Handle,0,0,5,STDEV_Buffer2);
   CopyBuffer(ENTROPIA_Handle,0,0,5,ENTROPIA_Buffer);
   CopyBuffer(HURST_Handle,0,0,5,HURST_Buffer1);
   CopyBuffer(HURST_Handle,0,0,5,HURST_Buffer2);
   CopyBuffer(RL_Handle,0,0,5,RL_Buffer1);
   CopyBuffer(RL_Handle,0,0,5,RL_Buffer2);
   CopyBuffer(RL_Handle,0,0,5,RL_Buffer3);
   CopyBuffer(RL_Handle,0,0,5,RL_Buffer4);
   CopyBuffer(RL_Handle,0,0,5,RL_Buffer5);
   
   bool flag = SERIES_SYNCHRONIZED;
   
//-- LEITURAS DE MERCADO
   
   long book_compra = BOOK_TYPE_BUY+BOOK_TYPE_BUY_MARKET; 
   long book_venda = BOOK_TYPE_SELL+BOOK_TYPE_SELL_MARKET;
   double volume_ordens_compra=SYMBOL_SESSION_BUY_ORDERS_VOLUME;
   double volume_ordens_venda=SYMBOL_SESSION_SELL_ORDERS_VOLUME;
   long vol_compras = SYMBOL_SESSION_BUY_ORDERS;
   long vol_vendas = SYMBOL_SESSION_SELL_ORDERS; 
   
//-- TESTE DE CONEXAO
/*      
   while(checkTrading()==false)
     {
      Alert("Negociacao nao permitida!");
      Print("Conta: ",myaccount.TradeAllowed());
      Print("Expert: ", myaccount.TradeExpert()); 
      Print("Sincronizacao: ",mysymbol.IsSynchronized());
      double ping =  TerminalInfoInteger(TERMINAL_PING_LAST)/1000; //-- Último valor conhecido do ping até ao servidor de negociação em microssegundos
      Print("Last ping: ",ping);
      Sleep(5000);
      }
         
//-- TESTANDO A CONEXAO PRINCIPAL DO TERMINAL COM O SERVIDOR DA CORRETORA  

   if(terminal.IsConnected()==false)
     {
      Print("Terminal nao conectado ao servidor da corretora!");
      SendMail("URGENTE - MT5 Desconectado!!!","Terminal desconectou do servidor da corretora! Verifque URGENTE!");
      RefreshRates();
      double ping =  TerminalInfoInteger(TERMINAL_PING_LAST)/1000; //-- Último valor conhecido do ping até ao servidor de negociação em microssegundos
      Print("Last ping antes da desconexao: ",ping);
      Sleep(10000);
     }

//-- VERIFICANDO SE O SERVIDOR PERMITE NEGOCIACAO

   if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
      Alert("Negociação automatizada é proibida para a conta ",AccountInfoInteger(ACCOUNT_LOGIN),
            " no lado do servidor de negociação");
*/            
//--- obtém spread a partir das propriedade do ativo 

   bool spreadfloat=SymbolInfoInteger(_Symbol,SYMBOL_SPREAD_FLOAT);

//-- Removendo EA do grafico
/*
   if(HorarioFechamento()==true && PositionSelect(_Symbol)==false)
     {
      ExpertRemove();
     }
   */
 }
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| FUNCAO DE TRADES                                                 |
//+------------------------------------------------------------------+
void Trades ()
  {
  
//-- PARAMETROS INICIAIS

   ResetLastError();
   CopyRates(_Symbol,_Period,0,5,candle);
   MqlTradeRequest request;
   MqlTradeResult  result;
   MqlTick price;
   SymbolInfoTick(_Symbol,price);
    
   ulong ticket = trade.RequestPosition(); 
   double sloss_long = SymbolInfoDouble(_Symbol,SYMBOL_BID)-stopLoss;  //-- Stop Loss Posicao Comprada
   double tprofit_long = SymbolInfoDouble(_Symbol,SYMBOL_BID)+TakeProfit;
   double sloss_short = SymbolInfoDouble(_Symbol,SYMBOL_ASK)+stopLoss; //-- Stop Loss Posicao Vendida
   double tprofit_short = SymbolInfoDouble(_Symbol,SYMBOL_ASK)-TakeProfit;

      
//-- ESTRATEGIA DE COMPRA

   if(PositionSelect(_Symbol)==false && HorarioEntrada()==true && maxTradesUm==0)
      {
      if(ENTROPIA_Buffer[0]>ENTROPIA_Buffer[1] && ENTROPIA_Buffer[1]>ENTROPIA_Buffer[2])
         {
        if(HURST_Buffer1[0]>0.65 && RL_Buffer1[0]>RL_Buffer1[1] && STDEV_Buffer1[0]>8.5)
          {
         trade.Buy(lote,_Symbol,0,sloss_long,tprofit_long,"Ordem de VENDA!");
         //-- VALIDACAO DE SEGURANCA

         if(trade.ResultRetcode()==10008 || trade.ResultRetcode()==10009)
           {
            Print("Ordem de VENDA enviada e executada com sucesso!");
            maxTradesUm++;
            TradeEmail();
           }
         else
           {
            Print("Erro ao enviar ordem! Erro #",GetLastError()," - ",trade.ResultRetcodeDescription());
            return;
           }
          }
        }
      }
      
//-- ESTRATEGIA DE VENDA

   if(PositionSelect(_Symbol)==false && HorarioEntrada()==true && maxTradesDois==0)
      {
      if(ENTROPIA_Buffer[0]<ENTROPIA_Buffer[1] && ENTROPIA_Buffer[1]<ENTROPIA_Buffer[2])
         {
       if(HURST_Buffer1[0]>0.65 && RL_Buffer1[0]<RL_Buffer1[1] && STDEV_Buffer1[0]>8.5)
         {
         trade.Sell(lote,_Symbol,0,sloss_short,tprofit_short,"Ordem de VENDA!");
         //-- VALIDACAO DE SEGURANCA

         if(trade.ResultRetcode()==10008 || trade.ResultRetcode()==10009)
           {
            Print("Ordem de VENDA enviada e executada com sucesso!");
            maxTradesDois++;
            TradeEmail();
           }
         else
           {
            Print("Erro ao enviar ordem! Erro #",GetLastError()," - ",trade.ResultRetcodeDescription());
            return;
           }
          }
        }
      }
      
//-- INSERINDO TRAILING STOP DE PASSO FIXO E LUCRO MINIMO

   if(usarTrailing==true && PositionSelect(_Symbol)==true && TrailingStop>0)
     {
      request.action = TRADE_ACTION_SLTP;
      request.symbol = _Symbol;
   
      ENUM_POSITION_TYPE posType=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double currentStop=PositionGetDouble(POSITION_SL);
      double openPrice=PositionGetDouble(POSITION_PRICE_OPEN);
      
      double minProfit=lucroMinimo;
      double step = passo;
      double trailStop=TrailingStop;
            
      double trailStopPrice;
      double currentProfit;
      double tp_fixo;
      
      if(posType==POSITION_TYPE_BUY)
        {
         trailStopPrice=SymbolInfoDouble(_Symbol,SYMBOL_BID)-trailStop;
         currentProfit=SymbolInfoDouble(_Symbol,SYMBOL_BID)-openPrice;
         tp_fixo=openPrice+tp_trailing;
                              
         if(trailStopPrice>=currentStop + step && currentProfit>=minProfit)
           {
            request.sl=trailStopPrice;
            request.tp=tp_fixo;
            bool ok=OrderSend(request,result);
           }
         }
         
       if(posType==POSITION_TYPE_SELL)
        {
         trailStopPrice=SymbolInfoDouble(_Symbol,SYMBOL_ASK)+trailStop;
         currentProfit=SymbolInfoDouble(_Symbol,SYMBOL_ASK)+openPrice;
         tp_fixo=openPrice-tp_trailing;
                     
         if(trailStopPrice<=currentStop-step && currentProfit>=minProfit)
           {
            request.sl=trailStopPrice;
            request.tp=tp_fixo;
            bool ok=OrderSend(request,result);
        }
      }
    }
       
//-- ENCERRANDO POSICAO DEVIDO AO LIMITE DE HORARIO (apos 17h30)

   if(HorarioFechamento()==true && PositionSelect(_Symbol)==true)
     {

      //-- Fecha a posicao pelo limite de horario

      trade.PositionClose(ticket,-1);

      //--- VALIDACAO DE SEGURANCA

      if(!trade.PositionClose(_Symbol))
        {
         //--- MENSAGEM DE FALHA
         Print("PositionClose() falhou. Return code=",trade.ResultRetcode(),
               ". Codigo de retorno: ",trade.ResultRetcodeDescription());

        }
      else
        {
         Print("PositionClose() executado com sucesso. codigo de retorno=",trade.ResultRetcode(),
               " (",trade.ResultRetcodeDescription(),")");
        }
     }

//-- ZERANDO OS VALORES DO PEDIDO E SEU RESULTADO

   ZeroMemory(request);
   ZeroMemory(result);

 }//-- Final da funcao Trades
//+------------------------------------------------------------------+  
//+------------------------------------------------------------------+
//| Funcao para enviar email ao iniciar trade                        |
//+------------------------------------------------------------------+
void TradeEmail()
  {
   string broker=AccountInfoString(ACCOUNT_COMPANY);
   string subject="Trade iniciado - EA: PEARSON-HURST - na corretora - "+ broker+"!";
   string text="O Trade foi iniciado no ativo: "+_Symbol+" .";
   SendMail(subject,text);
  }
//+------------------------------------------------------------------+ 
//+------------------------------------------------------------------+
//| Refreshes the symbol quotes data                                 |
//+------------------------------------------------------------------+
bool RefreshRates(void)
  {
//--- refresh rates
   if(!mysymbol.RefreshRates())
     {
      Print("Falha com dados de preco!");
      return(false);
     }
//--- protection against the return value of "zero"
   if(mysymbol.Ask()==0 || mysymbol.Bid()==0)
      return(false);
//---
   return(true);
  }  
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//|VALIDACAO DOS HORARIOS                                            |
//+------------------------------------------------------------------+

   bool HorarioEntrada()
      {
       TimeToStruct(TimeCurrent(),horario_atual);

      if(horario_atual.hour >= horario_inicio.hour && horario_atual.hour <= horario_termino.hour)
   {
      // Hora atual igual a de início
      if(horario_atual.hour == horario_inicio.hour)
         // Se minuto atual maior ou igual ao de início => está no horário de entradas
         if(horario_atual.min >= horario_inicio.min)
            return true;
         // Do contrário não está no horário de entradas
         else
            return false;
      
      // Hora atual igual a de término
      if(horario_atual.hour == horario_termino.hour)
         // Se minuto atual menor ou igual ao de término => está no horário de entradas
         if(horario_atual.min <= horario_termino.min)
            return true;
         // Do contrário não está no horário de entradas
         else
            return false;
      
      // Hora atual maior que a de início e menor que a de término
      return true;
   }
   
   // Hora fora do horário de entradas
   return false;
}


bool HorarioFechamento()
     {
      TimeToStruct(TimeCurrent(),horario_atual);
      
     
     // Hora dentro do horário de fechamento
   if(horario_atual.hour >= horario_fechamento.hour)
   {
      // Hora atual igual a de fechamento
      if(horario_atual.hour == horario_fechamento.hour)
         // Se minuto atual maior ou igual ao de fechamento => está no horário de fechamento
         if(horario_atual.min >= horario_fechamento.min)
            return true;
         // Do contrário não está no horário de fechamento
         else
            return false;
      
      // Hora atual maior que a de fechamento
      return true;
   }
   
   // Hora fora do horário de fechamento
   return false;
}
//+------------------------------------------------------------------+  
//+------------------------------------------------------------------+
//|  Checks if our Expert Advisor can go ahead and perform trading   |
//+------------------------------------------------------------------+
bool checkTrading()
  {
   bool can_trade=false;
// check if terminal is syncronized with server, etc
   if(myaccount.TradeAllowed() && myaccount.TradeExpert() && mysymbol.IsSynchronized())
     {
      // do we have enough bars?
      int mbars=Bars(_Symbol,_Period);
      if(mbars>0)
        {
         can_trade=true;
        }
     }
   return(can_trade);
  }
//+--------------------------------------------------------------------+
//| Retorna verdadeiro detectando nova barra, do contrário será falso  |
//+--------------------------------------------------------------------+
bool NewBarDetect()
  {
   datetime times[];
   if(CopyTime(_Symbol,_Period,0,1,times)<1)
      return false;
   if(times[0] == TimeLastBar)return false;
   TimeLastBar = times[0];
   return true;
  }
//+--------------------------------------------------------------------+
//+------------------------------------------------------------------+ 
//| Verifica se um modo de preenchimento específico é permitido      | 
//+------------------------------------------------------------------+ 
bool IsFillingTypeAllowed(string symbol,int fill_type)
  {
//--- Obtém o valor da propriedade que descreve os modos de preenchimento permitidos 
   int filling=(int)SymbolInfoInteger(symbol,SYMBOL_FILLING_MODE);
//--- Retorna true, se o modo fill_type é permitido 
   return((filling & fill_type)==fill_type);
  }
//+------------------------------------------------------------------+
//|VERIFICA VOLUMES DE TICKS NOS SENTIDOS BUY/SELL                   |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
bool testeTicksSell()
{
   if(sumVolSell>sumVolBuy)
     {
      return(true);
     }
     else
       {
        return(false);
       }
}

//+------------------------------------------------------------------+
bool testeTicksBuy()
{
   if(sumVolBuy>sumVolSell)
     {
      return(true);
     }
     else
       {
        return(false);
       }
}

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+ 
//| OBTENDO MOTIVOS DA DESINICIALIZACAO                              | 
//+------------------------------------------------------------------+ 
string getUninitReasonText(int reasonCode)
  {
   string text="";
//--- 
   switch(reasonCode)
     {
      case REASON_ACCOUNT:
         text="Alterações nas configurações de conta!";break;
      case REASON_CHARTCHANGE:
         text="O período do símbolo ou gráfico foi alterado!";break;
      case REASON_CHARTCLOSE:
         text="O gráfico foi encerrado!";break;
      case REASON_PARAMETERS:
         text="Os parâmetros de entrada foram alterados por um usuário!";break;
      case REASON_RECOMPILE:
         text="O programa "+__FILE__+" foi recompilado!";break;
      case REASON_REMOVE:
         text="O programa "+__FILE__+" foi excluído do gráfico!";break;
      case REASON_TEMPLATE:
         text="Um novo modelo foi aplicado!";break;
      default:text="Outro motivo!";
     }
//--- 
   return text;
  }
//+------------------------------------------------------------------+

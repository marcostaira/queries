do begin

/*
Autor: Marcos M Taira
Descrição: Query para SAP HANA do Quadro do Ativo. Nas análises e testes acredito que chega a 98% de acertividade.
Obs.: o Quadro do ativo não gera uma consulta pronta, foi necessário várias horas para desenvolvimento.
Data: 02/02/2024
Uso: Ao utilizar uma Query minha, mesmo que parte dela, deixe os créditos.
*/

declare dataini timestamp := {?datede};
declare datafim timestamp := {?datefim};

SELECT distinct T4."BalanceAct", T5."AcctName", T3."Code", T3."Name", T0."ItemCode", T0."ItemName"
, ifnull(T6."OcrCode", '0') as "OcrCode"
, T8."APCHist", T1."DprStart"
	,T1."UsefulLife" , T1."RemainLife", T1."DprType", T8."APC"
	, (T8."OrDpAcc" + (SELECT SUM(T00."OrdDprPlan") FROM "ODPV" T00  
			WHERE T00."ItemCode" = T0."ItemCode"  AND  T00."DprArea" = T1."DprArea" AND T00."PeriodCat" = T1."PeriodCat"  AND T00."ToDate" <= :dataini )) "OrDpAcc"
	, T8."WriteUpAcc", (T8."APC" - T8."OrDpAcc" - (SELECT SUM(T00."OrdDprPlan") FROM "ODPV" T00  
			WHERE T00."ItemCode" = T0."ItemCode"  AND  T00."DprArea" = T1."DprArea" AND T00."PeriodCat" = T1."PeriodCat"  AND T00."ToDate" <= :dataini )) "NBV"
	,T10."LineTotal" "Capitalization"
	,(SELECT T00."APC" FROM  "FIX1" T00  INNER  JOIN "OFIX" T10  ON  T10."AbsEntry" = T00."AbsEntry"   
 		WHERE T00."ItemCode" = T0."ItemCode" AND  T00."DprArea" = T1."DprArea" AND  T10."Canceled" = ('N')  
 		AND  T00."PeriodCat" = T1."PeriodCat"  AND  T00."TransType" in (210,220)) "Retired APC"
	,(SELECT CASE WHEN D."Appr" <> 0 THEN D."Appr" WHEN D."TransAmnt" <> 0 THEN (D."APC"-D."OrdDpr") END FROM FIX1 D 
		WHERE D."PeriodCat" = T1."PeriodCat" and D."TransType" in (210,220) AND D."ItemCode" = T0."ItemCode") "Retired NBV"
		
	,(SELECT T00."APC" FROM  "FIX1" T00  INNER  JOIN "OFIX" T10  ON  T10."AbsEntry" = T00."AbsEntry"   
 		WHERE T00."ItemCode" = T0."ItemCode" AND  T00."DprArea" = T1."DprArea" AND  T10."Canceled" = ('N')  
 		AND  T00."PeriodCat" = T1."PeriodCat"  AND  T00."TransType" in (310,320)) "Transferred APC"
	,(SELECT CASE WHEN D."Appr" <> 0 THEN D."Appr" WHEN D."TransAmnt" <> 0 THEN (D."APC"-D."OrdDpr") END FROM FIX1 D 
		WHERE D."PeriodCat" = T1."PeriodCat" and D."TransType" in (310,320) AND D."ItemCode" = T0."ItemCode") "Transferred NBV"
	
	,(SELECT FIRST_VALUE("Appr" order by "AbsEntry" DESC) FROM FIX1 WHERE "PeriodCat" = T1."PeriodCat" AND "TransType" = 550 AND "ItemCode" = T0."ItemCode" ) "Write-Up"
	
	,(SELECT sum(T00."OrdDprPlan") FROM  "ODPV" T00 WHERE T00."ItemCode" = T0."ItemCode" AND  T00."PeriodCat" = T1."PeriodCat"  
			AND  T00."DprArea" = T1."DprArea" AND T00."FromDate" >= :dataini AND T00."ToDate" <= :datafim) "Depreciation"
	,CASE WHEN (SELECT T00."APC" FROM  "FIX1" T00  INNER  JOIN "OFIX" T10  ON  T10."AbsEntry" = T00."AbsEntry"   
 		WHERE T00."ItemCode" = T0."ItemCode" AND  T00."DprArea" = T1."DprArea" AND  T10."Canceled" = ('N')  
 		AND  T00."PeriodCat" = T1."PeriodCat"  AND  T00."TransType" in (210,220)) <> 0 THEN 0
 		ELSE (T8."APC" + ifnull(T10."LineTotal",0)) END "APC on End Date"
	,((T8."APC" - T8."OrDpAcc")-(SELECT sum(T00."OrdDprPost") FROM  "ODPV" T00 WHERE T00."ItemCode" = T0."ItemCode" AND  T00."PeriodCat" = T1."PeriodCat"  AND  T00."DprArea" = T1."DprArea"))"NBV on End Date"
	
	,CASE WHEN ((SELECT T00."APC" FROM  "FIX1" T00  INNER  JOIN "OFIX" T10  ON  T10."AbsEntry" = T00."AbsEntry"   
 		WHERE T00."ItemCode" = T0."ItemCode" AND  T00."DprArea" = T1."DprArea" AND  T10."Canceled" = ('N')  
 		AND  T00."PeriodCat" = T1."PeriodCat"  AND  T00."TransType" in (210,220)) <> 0) THEN 0 
 		ELSE (T8."OrDpAcc"+(SELECT sum(T00."OrdDprPost") FROM  "ODPV" T00 WHERE T00."ItemCode" = T0."ItemCode" AND  T00."PeriodCat" = T1."PeriodCat"  AND  T00."DprArea" = T1."DprArea")) END "Depr. on End Date"
	
	,(T8."OrDpAcc"+(SELECT sum(T00."OrdDprPost") FROM  "ODPV" T00 WHERE T00."ItemCode" = T0."ItemCode" AND  T00."PeriodCat" = T1."PeriodCat"  AND  T00."DprArea" = T1."DprArea")) "Accum. Depr. on End Date"
FROM "OITM" T0  
LEFT JOIN "ITM7" T1  ON  T0."ItemCode" = T1."ItemCode"   
LEFT JOIN "ACS1" T2  ON  T2."DprAreaID" = T1."DprArea"  AND  T2."Code" = T0."AssetClass"   
LEFT JOIN "OACS" T3  ON  T2."Code" = T3."Code"
LEFT JOIN "OADT"  T4 ON T4."Code" =  T2."AcctDtn"
LEFT JOIN "OACT" T5 ON T4."BalanceAct" = T5."AcctCode"
LEFT JOIN "ITM6" T6 ON T6."ItemCode" = T0."ItemCode"
LEFT JOIN "ITM8" T8 ON T8."ItemCode" = T0."ItemCode" AND T1."PeriodCat" = T8."PeriodCat"
LEFT JOIN (SELECT A."PeriodCat", B."ItemCode", B."LineTotal"
	FROM "OACQ" A INNER JOIN "ACQ1" B ON A."DocEntry" = B."DocEntry"
	
) T10 ON T10."PeriodCat" = T1."PeriodCat" AND T10."ItemCode" = T0."ItemCode"

WHERE T2."Active" = ('Y')  AND  T1."DprArea" = ('1')  AND  T1."PeriodCat" = YEAR(:dataini)  AND  T0."AcqDate" <= :dataini
	AND  ((T0."RetDate" IS NOT NULL   AND  T0."RetDate" >= :datafim ) OR  T0."RetDate" IS NULL   OR  T3."AssetType" = ('L') ) 
	AND  T0."VirtAstItm" <> ('Y') 

ORDER BY  T0."ItemCode";

end;

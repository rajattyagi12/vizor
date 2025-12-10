/* PowerBI initialization and safety script
   - Create PowerBI database if missing
   - Ensure core tables exist
   - Create/refresh supporting stored procedures
*/

IF DB_ID('PowerBI') IS NULL
BEGIN
    PRINT 'Creating PowerBI database...';
    CREATE DATABASE [PowerBI];
END
GO

USE [PowerBI];
GO

-- Create PowerBI_RefreshLog if it does not exist
IF NOT EXISTS (
    SELECT 1
    FROM sys.objects
    WHERE object_id = OBJECT_ID(N'[dbo].[PowerBI_RefreshLog]')
      AND type = 'U'
)
BEGIN
    CREATE TABLE [dbo].[PowerBI_RefreshLog](
        [JobID] [int] IDENTITY(1,1) NOT NULL,
        [RefreshTypeID] [int] NOT NULL,
        [Input] [int] NOT NULL,
        [InputType] [varchar](8000) NOT NULL,
        [UserID] [varchar](8000) NOT NULL,
        [Request_Date] [datetime2](7) NOT NULL,
        [Batch_Start_Date] [datetime2](7) NULL,
        [Processing_Start_Date] [datetime2](7) NULL,
        [Completion_Date] [datetime2](7) NULL,
        [Status] [int] NOT NULL
    ) ON [PRIMARY];
END
GO

-- Create Report_RoundTable_Master_Response if it does not exist
IF NOT EXISTS (
    SELECT 1
    FROM sys.objects
    WHERE object_id = OBJECT_ID(N'[dbo].[Report_RoundTable_Master_Response]')
      AND type = 'U'
)
BEGIN
    CREATE TABLE [dbo].[Report_RoundTable_Master_Response](
        [Row_ID] [int] IDENTITY(1,1) NOT NULL,
        [Survey_ID] [int] NOT NULL,
        [Report_ID] [int] NOT NULL,
        [PeriodID] [varchar](6) NOT NULL,
        [PeriodDate] [date] NOT NULL,
        [RoundTableName] [varchar](8000) NOT NULL,
        [RoundTableID] [int] NOT NULL,
        [Frequency] [varchar](20) NOT NULL,
        [Frequency_ID] [int] NOT NULL,
        [Entry_Type] [varchar](100) NOT NULL,
        [Client_ID] [int] NULL,
        [Section_ID] [int] NULL,
        [SectionName] [varchar](8000) NULL,
        [ParentQuestion_ID] [int] NULL,
        [Question_ID] [int] NULL,
        [ParentQuestion] [varchar](8000) NULL,
        [Question] [varchar](8000) NULL,
        [FullContextQuestion] [varchar](8000) NULL,
        [QuestionDefinition] [varchar](8000) NULL,
        [QuestionCalculation] [varchar](8000) NULL,
        [QuestionCalculation_Text] [varchar](8000) NULL,
        [Response] [varchar](8000) NULL,
        [Previous_Response] [varchar](8000) NULL,
        [Response_Numeric] [numeric](16, 6) NULL,
        [Previous_Response_Numeric] [numeric](16, 6) NULL,
        [PreviousYear_Response_Numeric] [numeric](16, 6) NULL,
        [Response_Text] [varchar](8000) NULL,
        [AnswerTypeDescriptions] [varchar](8000) NULL,
        [AnswerControlTypeDescriptions] [varchar](8000) NULL,
        [DecimalsOnReport] [int] NULL,
        [Footnote] [varchar](8000) NULL,
        [PoPPercentageChange] [numeric](14, 2) NULL,
        [Previous_PoPPercentageChange] [numeric](14, 2) NULL,
        [PoPeriodPercentRangeTypeID] [varchar](20) NULL,
        [YoYPercentageChange] [numeric](14, 2) NULL,
        [Previous_YoYPercentageChange] [numeric](14, 2) NULL,
        [YoYPercentageChangeRangeTypeID] [varchar](20) NULL,
        [Mean] [numeric](16, 6) NULL,
        [Previous_Mean] [numeric](16, 6) NULL,
        [PreviousYear_Mean] [numeric](16, 6) NULL,
        [Olympic_Mean] [numeric](16, 6) NULL,
        [Mean_PoPPercentageChange] [numeric](14, 2) NULL,
        [Mean_YoYPercentageChange] [numeric](14, 2) NULL,
        [Rating] [int] NULL,
        [Performance_Category] [varchar](10) NULL,
        [PerformanceCategory_Main_Ranking] [int] NULL,
        [PerformanceCategory_Sub_Ranking] [int] NULL,
        [PerformanceCategory_PageNum_MainTab] [int] NULL,
        [PerformanceCategory_Position_MainTab] [int] NULL,
        [PerformanceCategory_PageNum_DrillDownTab] [int] NULL,
        [PerformanceCategory_Position_DrillDownTab] [int] NULL,
        [IsReportable_Flag] [int] NULL,
        [Sentiment_Flag] [int] NULL,
        [ShowonDashboard_Flag] [int] NULL,
        [VarianceCalculation_Flag] [int] NULL,
        [ShowIndividualData_Flag] [int] NULL,
        [ExecSummary_SortKey] [int] NULL,
        [Current_Response_Rank] [varchar](10) NULL,
        [Previous_Response_Rank] [varchar](10) NULL,
        [Ranking] [int] NULL,
        [Internal_External_Flag] [int] NULL,
        [ReportSectionSortKey] [int] NULL,
        [QuestionBlockSortKey] [int] NULL,
        [ReportQuestionsSortKey] [int] NULL,
        [Created_Date] [datetime2](7) NOT NULL,
        [Updated_Date] [datetime2](7) NOT NULL,
        [SlicerControlSortKey] [int] NULL,
        [MasterSortKey] [int] NULL
    ) ON [PRIMARY];
END
GO

/****** Stored Procedure: [dbo].[0_AdHoc_PowerBI_DataRefresh] ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[0_AdHoc_PowerBI_DataRefresh]
    @RefreshTypeID INT,
    @Input INT,
    @InputType Varchar(8000),
    @UserID Varchar(8000)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1
        FROM [PowerBI].[dbo].[PowerBI_RefreshLog]
        WHERE RefreshTypeID = @RefreshTypeID
          AND Input = @Input
          AND InputType = @InputType
          AND [Status] = 0
    )
    BEGIN 
        INSERT INTO [PowerBI].[dbo].[PowerBI_RefreshLog]
        (
            [RefreshTypeID],
            [Input],
            [InputType],
            [UserID],
            [Request_Date],
            [Batch_Start_Date],
            [Processing_Start_Date],
            [Completion_Date],
            [Status]
        )
        SELECT
            @RefreshTypeID,
            @Input,
            @InputType,
            @UserID,
            GETDATE() AS [Request_Date],
            NULL AS [Batch_Start_Date],
            NULL AS [Processing_Start_Date],
            NULL AS [Completion_Date],
            0 AS [Status];
    END
    ELSE
    BEGIN
        PRINT 'There is already a refresh scheduled';
    END;

    IF @RefreshTypeID IN (1, 2)
    BEGIN
        IF NOT EXISTS (
            SELECT 1
            FROM [PowerBI].[dbo].[PowerBI_RefreshLog]
            WHERE RefreshTypeID = 0
              AND Input = 0
              AND InputType = 'Internal'
              AND [Status] = 0
        )
        BEGIN 
            INSERT INTO [PowerBI].[dbo].[PowerBI_RefreshLog]
            (
                [RefreshTypeID],
                [Input],
                [InputType],
                [UserID],
                [Request_Date],
                [Batch_Start_Date],
                [Processing_Start_Date],
                [Completion_Date],
                [Status]
            )
            SELECT
                0,
                0,
                'Internal',
                @UserID,
                GETDATE() AS [Request_Date],
                NULL AS [Batch_Start_Date],
                NULL AS [Processing_Start_Date],
                NULL AS [Completion_Date],
                0 AS [Status];
        END;
    END;
END
GO

/****** Stored Procedure: [dbo].[PowerBI_External_Flag_Update] ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[PowerBI_External_Flag_Update]
    @SurveyID INT,
    @Show_Hide Varchar(10),
    @userID Varchar(8000)
AS
BEGIN
    SET NOCOUNT ON;

    IF @Show_Hide = 'Show'
    BEGIN
        UPDATE [PowerBI].[dbo].[Report_RoundTable_Master_Response]
        SET [Internal_External_Flag] = 1,
            Updated_Date = GetDate()
        WHERE Survey_ID = @SurveyID;

        EXECUTE Powerbi.dbo.[0_AdHoc_PowerBI_DataRefresh] 0, 0, 'External', @userID;
    END

    IF @Show_Hide = 'Hide'
    BEGIN
        UPDATE [PowerBI].[dbo].[Report_RoundTable_Master_Response]
        SET [Internal_External_Flag] = 0,
            Updated_Date = GetDate()
        WHERE Survey_ID = @SurveyID;

        EXECUTE Powerbi.dbo.[0_AdHoc_PowerBI_DataRefresh] 0, 0, 'External', @userID;
    END
END
GO


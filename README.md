####Overview
Using the latest available image for SharePoint 2013 in the azure gallery, it will create a highly available SharePoint farm and in the process setup Active Directory, Windows Failover Cluster and SQL Server Availability Group for the SharePoint databases.

####Virtual Machines (VMs)
1.Two VMs will be created for setting Active Directory and they will act as the primary and secondary DNS. 
2.The number of SQL VMs is controlled by the input parameter 'NumberOfSQLNodes, but a minimum of two is needed for creating the availability group. The minimum recommended size for SQL VM is 'Large'.
3.A single VM for having a 'Node and File Share Majority' quorum configuration in the failover cluster, with the VM acting as a 'file share witness'.
4.The number of app server VMs in the farm is controlled by the input parameter 'AppServerCount'.
5.The number of web server VMs in the farm is controlled by the input parameter 'WebServerCount'.

####Limitations
Following are the limitations of this template. Users can fork this repository and customize the template to fix them or wait for our periodic updates.
> - The template adds just a single data disk of 40 GB to the SQL VMs.
> - The template does not support the scenario where Active Directory setup has already been performed in the Azure Virtual Network.
> - The template does not support the scenario where SQL Server Availability Group already exists in the specified Azure Virtual Network.

####References
Please refer to the following links for more information on SQL Server Availability Groups.
> - [SharePoint 2013 on Azure](http://msdn.microsoft.com/en-us/library/dn275958.aspx)
> - [SharePoint 2013 and SQL Server AlwaysOn](http://blogs.msdn.com/b/sambetts/archive/2013/04/24/sharepoint-2013-and-sql-server-alwayson-high-availability-sharepoint.aspx)


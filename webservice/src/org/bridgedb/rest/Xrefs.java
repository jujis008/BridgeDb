// BridgeDb,
// An abstraction layer for identifer mapping services, both local and online.
// Copyright 2006-2009 BridgeDb developers
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
package org.bridgedb.rest;

import java.util.HashSet;
import java.util.List;
import java.util.Set;

import org.bridgedb.DataSource;
import org.bridgedb.Xref;
import org.bridgedb.rdb.IDMapperRdb;
import org.restlet.data.Status;
import org.restlet.resource.Get;
import org.restlet.resource.ResourceException;

/**
 * Resource that handles the xref queries
 */
public class Xrefs extends IDMapperResource {
	List<IDMapperRdb> mappers;
	Xref xref;
	DataSource targetDs;
	
	protected void doInit() throws ResourceException {
		try {
		    System.out.println( "Xrefs.doInit start" );
			//Required parameters
			String org = (String)getRequest().getAttributes().get(IDMapperService.PAR_ORGANISM);
			mappers = getIDMappers(org);

			String id = (String)getRequest().getAttributes().get(IDMapperService.PAR_ID);
			String dsName = (String)getRequest().getAttributes().get(IDMapperService.PAR_SYSTEM);
			DataSource dataSource = parseDataSource(dsName);
			if(dataSource == null) {
				throw new IllegalArgumentException("Unknown datasource: " + dsName);
			}
			xref = new Xref(id, dataSource);
			
			//Optional parameters
			String targetDsName = (String)getRequest().getAttributes().get(IDMapperService.PAR_TARGET_SYSTEM);
			targetDs = parseDataSource(targetDsName);
		} catch(Exception e) {
			throw new ResourceException(e);
		}
	}

	@Get
	public String getXrefs() {
	   System.out.println( "Xrefs.getXrefs() start" );
		try {
			//The result set
			Set<Xref> xrefs = new HashSet<Xref>();

			for(IDMapperRdb mapper : mappers) {
				if(targetDs == null) {
					xrefs.addAll(mapper.mapID(xref, null));
				} else {
					Set<DataSource> tgtSet = new HashSet<DataSource>();
					tgtSet.add (targetDs);
					xrefs.addAll(mapper.mapID(xref, tgtSet));
				}
			}
					
			StringBuilder result = new StringBuilder();
			for(Xref x : xrefs) {
				result.append(x.getId());
				result.append("\t");
				result.append(x.getDataSource().getFullName());
				result.append("\n");
			}
			
			return result.toString();
		} catch(Exception e) {
			e.printStackTrace();
			setStatus(Status.SERVER_ERROR_INTERNAL);
			return e.getMessage();
		}
	}

}
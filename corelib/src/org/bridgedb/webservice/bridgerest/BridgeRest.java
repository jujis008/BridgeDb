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
package org.bridgedb.webservice.bridgerest;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.net.MalformedURLException;
import java.net.URL;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import org.bridgedb.AttributeMapper;
import org.bridgedb.BridgeDb;
import org.bridgedb.DataSource;
import org.bridgedb.IDMapper;
import org.bridgedb.IDMapperCapabilities;
import org.bridgedb.IDMapperException;
import org.bridgedb.Xref;
import org.bridgedb.webservice.IDMapperWebservice;

/**
 * IDMapper implementation for BridgeRest, the REST interface of BridgeDb itself.
 */
public class BridgeRest extends IDMapperWebservice implements AttributeMapper
{
    static {
		BridgeDb.register ("idmapper-bridgerest", new Driver());
	}

	private final static class Driver implements org.bridgedb.Driver {
        /** private constructor to prevent outside instantiation. */
		private Driver() { } 

        /** {@inheritDoc} */
        public IDMapper connect(String location) throws IDMapperException  {
            return new BridgeRest(location);
        }
    }
	
	private final String baseUrl;
	
	/**
	 * @param baseUrl base Url, e.g. http://webservice.bridgedb.org/Human or
	 * 	http://localhost:8182
	 */
	BridgeRest (String baseUrl)
	{
		this.baseUrl = baseUrl;
	}
	
	private boolean isConnected = true;
	
	/** {@inheritDoc} */
	public void close() throws IDMapperException { isConnected = false; }

	/** {@inheritDoc} */
	public Set<Xref> freeSearch(String text, int limit)
			throws IDMapperException 
	{
		try
		{
			URL url = new URL (baseUrl + "/search/id/" + text);
			Set<Xref> result = new HashSet<Xref>();
			result.addAll (parseRefs(url));
			return result;
		}
		catch (MalformedURLException ex)
		{
			throw new IDMapperException (ex);
		} 
		catch (IOException ex) 
		{
			throw new IDMapperException (ex);
		}
	}

	/** {@inheritDoc} */
	public IDMapperCapabilities getCapabilities() {
		// TODO Auto-generated method stub
		throw new UnsupportedOperationException();
	}

	/** {@inheritDoc} */
	public boolean isConnected() {
		return isConnected;
	}

	/** {@inheritDoc} */
	public Map<Xref, Set<Xref>> mapID(Set<Xref> srcXrefs,
			Set<DataSource> tgtDataSources) throws IDMapperException 
	{
		Map<Xref, Set<Xref>> result = new HashMap<Xref, Set<Xref>>();
		for (Xref ref : srcXrefs)
		{
			result.put (ref, mapID(ref, tgtDataSources));
		}
		return result;
	}

	/** {@inheritDoc} */
	public Set<Xref> mapID(Xref src,
			Set<DataSource> tgtDataSources) throws IDMapperException 
	{
		try
		{
			URL url = new URL(baseUrl + "/model/" + src.getDataSource().getSystemCode() + "/" + src.getId() + "/xrefs");
			Set<Xref> result = new HashSet<Xref>();
			for (Xref dest : parseRefs(url))
			{
				if (tgtDataSources == null ||
					tgtDataSources.contains(dest.getDataSource()))
				{
					result.add (dest);
				}
			}
			return result;
		}
		catch (IOException ex)
		{
			throw new IDMapperException(ex);
		}
	}
	
	/** 
	 * helper, opens url and parses Xrefs.
	 * Xrefs are expected as one per row, id <tab> system
	 * @param url URL to open
	 * @return parsed Xrefs
	 * @throws IOException */
	private List<Xref> parseRefs(URL url) throws IOException
	{
		List<Xref> result = new ArrayList<Xref>();
		BufferedReader reader = new BufferedReader(new InputStreamReader(url.openStream()));
		String line;
		while ((line = reader.readLine()) != null)
		{
			String[] fields = line.split("\t");
			Xref dest = new Xref (fields[0], DataSource.getByFullName(fields[1]));
			result.add (dest);
		}
		return result;
	}

	/** {@inheritDoc} */
	public boolean xrefExists(Xref xref) throws IDMapperException {
		// TODO Auto-generated method stub
		throw new UnsupportedOperationException();
	}

	/** {@inheritDoc} */
	public Map<Xref, String> freeAttributeSearch(String query, String attrType,
			int limit) throws IDMapperException {
		// TODO Auto-generated method stub
		throw new UnsupportedOperationException();
	}

	/** {@inheritDoc} */
	public Set<String> getAttributes(Xref ref, String attrType)
			throws IDMapperException {
		// TODO Auto-generated method stub
		throw new UnsupportedOperationException();
	}
}